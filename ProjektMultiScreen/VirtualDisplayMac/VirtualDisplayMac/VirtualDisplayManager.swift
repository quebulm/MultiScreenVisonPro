//
//  VirtualDisplayManager.swift
//  VirtualDisplayMac
//
//  Created by Quentin Ulmer on 09.02.24.
//

import Foundation
import ScreenCaptureKit
import NIO
import NIOFoundationCompat
import VideoToolbox



class VirtualDisplayManager: NSObject {
    var displayStream: SCStream?
    var streamOutput: StreamOutput?
    var frameCount: Int64 = 0
    var virtualDisplay: VirtualDisplayInstance?

    
    override init() {
        super.init()
    }
    
    
    func initializeAndStartStream(id: UInt16) async {
        // Step 1: Initialize the virtual display and identify its display ID
        self.virtualDisplay = await VirtualDisplayInstance.createAndIdentifyDisplay(id: id)

        guard let virtualDisplay = self.virtualDisplay else {
            print("Virtual display not initialized.")
            return
        }

        do {
            // `virtualDisplay.id` is of type UInt32 and matches an `SCDisplay`'s `displayID`

            // Step 2: Retrieve the updated list of available displays after virtual display creation
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Step 3: Find the display that matches the virtualDisplay.id
            if let matchedDisplay = availableContent.displays.first(where: { $0.displayID == virtualDisplay.id }) {
                // Create a content filter for the matched display
                let filter = SCContentFilter(display: matchedDisplay, excludingWindows: [])

                
                // Continue with stream configuration and initialization using this filter
                // Step 4: Configure the stream with matched display settings
                let streamConfig = SCStreamConfiguration()
                
                streamConfig.width = virtualDisplay.width
                streamConfig.height = virtualDisplay.height
                // Set the capture interval at 60 fps.
                streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                // Increase the depth of the frame queue to ensure high fps at the expense of increasing
                // the memory footprint of WindowServer.
                streamConfig.queueDepth = 5
                
                // Initialize and start the stream with general content and configuration
                let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
                // Create Dispatch Queue
                let videoSampleBufferQueue = DispatchQueue(label: "com.example.myApp.videoSampleBufferQueue")

                // Create an Instanz of StreamOutput
                let streamOutput = StreamOutput(sampleHandlerQueue: videoSampleBufferQueue)
                streamOutput.setupCompressionSession()
                
                streamOutput.setupTCPConnection(to: "localhost", port: id)

                // Adds StreamOutput to SCStream
                try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)

                self.displayStream = stream // Store the stream instance to keep it alive
                self.streamOutput = streamOutput
                try await stream.startCapture()
                
                
            } else {
                print("Failed to find a matching display for the given virtualDisplay.id")
            }
        } catch {
            print("Failed to start screen capture: \(error.localizedDescription)")
        }
    }
    
}

func compressionOutputCallback(outputCallbackRefCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
    guard status == noErr, let sampleBuffer = sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else {
        print("Error or sample buffer not ready")
        return
    }

    // Extract 'self' from 'refcon'
    guard let refCon = outputCallbackRefCon else { return }
    let streamOutput = Unmanaged<StreamOutput>.fromOpaque(refCon).takeUnretainedValue()

    // Check if format description is available to extract SPS & PPS data
    if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
        // Check for video media type
        let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
        if mediaType == kCMMediaType_Video {
            // Attempt to extract SPS and PPS if they have not been extracted yet
            if streamOutput.spsData == nil || streamOutput.ppsData == nil {
                streamOutput.extractSPSandPPS(from: formatDescription)
            }
        }
    }

    // Compressed frame is ready, now send it over TCP
    streamOutput.sendCompressedFrameTCP(sampleBuffer: sampleBuffer)
}





class StreamOutput: NSObject,SCStreamOutput {
    
    let sampleHandlerQueue: DispatchQueue
    var channel: Channel?
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    var compressionSession: VTCompressionSession?
    
    var framessend = 0
    
    private let context: CIContext
    
    var spsData: Data?
    var ppsData: Data?

    func extractSPSandPPS(from formatDescription: CMFormatDescription) {
        var spsSize: Int = 0
        var ppsSize: Int = 0
        var spsCount: Int = 0
        var ppsCount: Int = 0
        var spsPointer: UnsafePointer<UInt8>?
        var ppsPointer: UnsafePointer<UInt8>?
        var nalUnitHeaderLength: Int32 = 0

        // Extract SPS
        let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: &nalUnitHeaderLength)

        // Extract PPS
        let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: &nalUnitHeaderLength)

        if spsStatus == noErr, ppsStatus == noErr, let spsPointer = spsPointer, let ppsPointer = ppsPointer {
            self.spsData = Data(bytes: spsPointer, count: spsSize)
            self.ppsData = Data(bytes: ppsPointer, count: ppsSize)
            
            print("SPS size: \(spsSize), PPS size: \(ppsSize)")
            print("SPS and PPS extracted and stored.")
            // first send SPS and PPS
            sendInitialSPSandPPS()

        } else {
            print("Failed to extract SPS/PPS data.")
        }
    }


    init(sampleHandlerQueue: DispatchQueue) {
            self.context = CIContext()
            self.sampleHandlerQueue = sampleHandlerQueue
        }
    
    deinit {
            // Cleans eventLoop
            try? eventLoopGroup.syncShutdownGracefully()
        }

    
    func setupTCPConnection(to ipAddress: String, port: UInt16) {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                // Config Bootstrap (z.B. Timeout, ChannelOptionen)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    return channel.eventLoop.makeSucceededFuture(())
                }
            bootstrap.connect(host: ipAddress, port: Int(port)).whenSuccess { channel in
                print("Verbunden mit \(ipAddress):\(port)")
                self.channel = channel
            }
        }

    func sendTCP(data: Data) {
        guard let channel = self.channel else {
            print("TCP connection is not established.")
            return
        }

        // Prepare the data for sending without appending an imageDataSeparator
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)

        // Send the data over the channel
        channel.writeAndFlush(buffer).whenComplete { result in
            switch result {
            case .success:
                print("Successfully sent data.")
            case .failure(let error):
                print("Error while sending: \(error)")
            }
        }
    }
    
    func sendInitialSPSandPPS() {
        guard let sps = spsData, let pps = ppsData else {
            print("SPS or PPS data not available.")
            return
        }

        var initData = Data()
        // Add Startcode then SPS-Data
        initData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        initData.append(sps)
        // Add starter code and then PPS data
        initData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        initData.append(pps)
        

        // Send the prepared data over TCP
        sendTCP(data: initData)
        print("SPS and PPS data sent over TCP.")
    }


    
    
    func sendCompressedFrameTCP(sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("No data buffer found in sample buffer.")
            return
        }

        var length = Int()
        var totalLength = Int()
        var dataPointer: UnsafeMutablePointer<Int8>?

        let result = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        if result != noErr || dataPointer == nil {
            print("Failed to access data. Result: \(result)")
            return
        }

        guard let pointer = dataPointer else {
            print("Data pointer is nil.")
            return
        }

        var annexBData = Data(capacity: totalLength + 4 * (totalLength / 4)) // Preallocate to avoid reallocations
        var offset = 0
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        while offset + 4 <= totalLength {
            let nalUnitLength = pointer.withMemoryRebound(to: UInt32.self, capacity: 1) { ptr -> Int in
                let networkOrderValue = ptr[offset / MemoryLayout<UInt32>.size]
                return Int(CFSwapInt32BigToHost(networkOrderValue))
            }
            offset += 4

            guard offset + nalUnitLength <= totalLength else {
                print("Invalid NAL unit length at offset \(offset - 4).")
                break
            }

            annexBData.append(contentsOf: startCode)

            // Directly append bytes from pointer to Data
            if let dataPointer = dataPointer {
                let uint8Pointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: UInt8.self)
                annexBData.append(uint8Pointer.advanced(by: offset), count: nalUnitLength)
            }

            offset += nalUnitLength
        }

        if !annexBData.isEmpty {
//            print("Total Annex-B data length: \(annexBData.count) bytes. Preparing to send over TCP.")
            sendTCP(data: annexBData)
            framessend += 1
            print("sended: \(framessend)")
        } else {
            print("No valid NAL units found to send.")
        }
    }






    
    func processFrameAndSendTCP(_ sampleBuffer: CMSampleBuffer) {
        print("entered processFrameAndSendTCP")
        // Ensure the compression session is set up
        guard compressionSession != nil else {
            print("Compression session is not set up")
            return
        }
        // Ensure the sampleBuffer contains video data
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            print("Sample buffer contains no samples")
            return
        }
        guard CMSampleBufferIsValid(sampleBuffer) else {
            print("Sample buffer is not valid")
            return
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("Sample buffer data is not ready")
            return
        }

        // Compress and send the frame using the compression session
        encodeFrame(sampleBuffer: sampleBuffer)
    }
    
    func setupCompressionSession() {
        let width = Int32(1920) // Use actual width
        let height = Int32(1080) // Use actual height
        createCompressionSession(width: width, height: height)
    }
    
    
    func createCompressionSession(width: Int32, height: Int32) {
        let imageBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var compressionSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264, // Or kCMVideoCodecType_HEVC for H.265
            encoderSpecification: nil,
            imageBufferAttributes: imageBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &compressionSession
        )

        if status != noErr {
            print("Error creating compression session: \(status)")
            return
        }

        // configure (Bitrate, Frame-Rate, Profil, etc.)
        let averageBitRate = [Int(1000 * 1000)] // bits per second
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_AverageBitRate, value: averageBitRate as CFTypeRef)
        let dataRateLimits = [averageBitRate, 1] as [Any] // Array in the form: [Data rate in bytes, Duration in seconds].
        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits as CFTypeRef)

        VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        self.compressionSession = compressionSession // Saving the session in your class.

        print("Compression session created with specific imageBufferAttributes")
    }

    func encodeFrame(sampleBuffer: CMSampleBuffer) {
        guard let compressionSession = compressionSession else {
            print("Compression session is not set up")
            return
        }
        
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let mediaType = CMFormatDescriptionGetMediaType(formatDescription)
            if mediaType == kCMMediaType_Video {
//                print("The sampleBuffer contains video data")
               
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let width = CVPixelBufferGetWidth(imageBuffer)
                    let height = CVPixelBufferGetHeight(imageBuffer)
//                    print("Image buffer dimensions: \(width)x\(height)")
                } else {
                    return
                }
            } else {
                print("The sampleBuffer doesn't contain video data, it contains \(mediaType)")
            }
        } else {
            print("No format description available for the sample buffer.")
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            print("Failed to get the image buffer from sample buffer")
            return
        }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        VTCompressionSessionEncodeFrame(compressionSession, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    }




    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        processFrameAndSendTCP(sampleBuffer)
    }
}


