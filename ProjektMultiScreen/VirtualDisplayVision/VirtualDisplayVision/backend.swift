//
//  backend.swift
//  VirtualDisplayVision
//
//  Created by Quentin Ulmer on 11.02.24.
//

// TCPImageReceiver.swift


import Foundation
import NIO
import UIKit
import AVFoundation
import VideoToolbox
import CoreMedia

// Global Variables for Decompression Session
var decompressionSession: VTDecompressionSession?
var spsData: Data?
var ppsData: Data?


// MARK: - ChannelInboundHandler for processing received data
final class ImageDataHandler: ChannelInboundHandler {
    var videoFormatDescription: CMVideoFormatDescription?
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    var port: Int
    
    init(port: Int) {
        self.port = port
    }
    
    
    var receivedData = Data()

    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = self.unwrapInboundIn(data)
        
        if let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) {
            receivedData.append(contentsOf: bytes)
//            print(bytes)

            // Extract and process all complete NAL units in the received data buffer.
            while let nalUnit = extractCompleteNALUnit(from: &receivedData) {
                self.processVideoFrame(nalUnit: nalUnit)
            }
        }
    }


    func findEarliestStartCode(in buffer: Data, from index: Data.Index) -> Range<Data.Index>? {
        let longStartCode = Data([0x00, 0x00, 0x00, 0x01])
        let searchRange = buffer[index...]

        if let foundLongStartCodeRange = searchRange.range(of: longStartCode) {
            return foundLongStartCodeRange
        }
        // no code found
        return nil
    }


    func extractCompleteNALUnit(from buffer: inout Data) -> Data? {
        
        // Search for the first start code
        guard let firstStartCodeRange = findEarliestStartCode(in: buffer, from: buffer.startIndex) else {
            return nil
        }
        
        let nextSearchStartIndex = firstStartCodeRange.upperBound
        
        // Search for the second start code in the remaining buffer
        guard let secondStartCodeRange = findEarliestStartCode(in: buffer, from: nextSearchStartIndex) else {
            return nil
        }
        
        let nalUnitRange = firstStartCodeRange.upperBound..<secondStartCodeRange.lowerBound
        
        
        if nalUnitRange.lowerBound >= buffer.startIndex && nalUnitRange.upperBound <= buffer.endIndex {
            // Extract the NAL unit from the buffer without the start code
            let nalUnit = buffer.subdata(in: nalUnitRange)
            // Update the buffer by removing everything up to the beginning of the second start code
            buffer.removeSubrange(0..<secondStartCodeRange.lowerBound)
            print("NalUnit Processed")
            return nalUnit
        } else {
            return nil
        }
    }




    
    func processVideoFrame(nalUnit: Data) -> Bool {
        
        // Extract the NAL unit type
        let nalUnitType = nalUnit.first! & 0x1F
        print("NAL Unit Type: \(nalUnitType)")
        
        
        switch nalUnitType {
        case 7:
            // Sequence Parameter Set (SPS)
            spsData = nalUnit
            printFoundDataSize(data: spsData, type: "SPS")
        case 8:
            // Picture Parameter Set (PPS)
            ppsData = nalUnit
            printFoundDataSize(data: ppsData, type: "PPS")
        case 1, 5:
            // Coded Slice of a Non-IDR Picture oder Coded Slice of an IDR Picture
            // Main Video Data
            guard let _ = spsData, let _ = ppsData else {
                print("SPS or PPS data not available.")
                return false
            }
            
            prepareVideoFormatDescription()
            
            guard videoFormatDescription != nil else {
                print("Video format description not available.")
                return false
            }
            
            guard let sampleBuffer = createCMSampleBufferFromNALUnit(nalUnit: nalUnit) else {
                print("Failed to create sample buffer.")
                return false
            }
            
            return decodeFrame(sampleBuffer: sampleBuffer)
        default:
                print("Unhandled NAL Unit Type: \(nalUnitType)")
                return false
            }

        
        return true
    }
    
//    func printFoundDataSize(data: Data?, type: String) {
//        guard let data = data else {
//            print("\(type) Data not found.")
//            return
//        }
//        // Druckt die Größe der Daten in Bytes.
//        print("Found \(type) Data with size: \(data.count) bytes")
//    }



    func decodeFrame(sampleBuffer: CMSampleBuffer) -> Bool {
        var infoFlags = VTDecodeInfoFlags(rawValue: 0)
        let result = VTDecompressionSessionDecodeFrame(decompressionSession!, sampleBuffer: sampleBuffer, flags: [], frameRefcon: nil, infoFlagsOut: &infoFlags)
        
        if result != noErr {
            print("Decoding failed. Error code: \(result)")
            return false
        }
        return true
    }


    func createCMSampleBufferFromNALUnit(nalUnit: Data) -> CMSampleBuffer? {
        // Convert the incoming data to a CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                        memoryBlock: UnsafeMutableRawPointer(mutating: (nalUnit as NSData).bytes),
                                                        blockLength: nalUnit.count,
                                                        blockAllocator: kCFAllocatorNull,
                                                        customBlockSource: nil,
                                                        offsetToData: 0,
                                                        dataLength: nalUnit.count,
                                                        flags: 0,
                                                        blockBufferOut: &blockBuffer)
        if status != kCMBlockBufferNoErr {
            print("BlockBuffer creation failed with error \(status)")
            return nil
        }
        
        // Create a CMSampleBuffer
        let sampleSizeArray = [nalUnit.count]
        var sampleBuffer: CMSampleBuffer?
        let sampleBufferStatus = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                                           dataBuffer: blockBuffer,
                                                           formatDescription: videoFormatDescription,
                                                           sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: sampleSizeArray,
                                                           sampleBufferOut: &sampleBuffer)
        if sampleBufferStatus != noErr {
            print("CMSampleBuffer creation failed with error \(sampleBufferStatus)")
            return nil
        }
        
        return sampleBuffer
    }


    func prepareVideoFormatDescription() {
        guard let sps = spsData, let pps = ppsData else {
            print("SPS or PPS data not available.")
            return
        }
        
        print("SPS size: \(sps.count) bytes, PPS size: \(pps.count) bytes")
        
        let parameterSetSizes = [sps.count, pps.count]
        
        sps.withUnsafeBytes { rawBufferPointer in
            guard let spsPointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                print("Error obtaining pointer to SPS.")
                return
            }
            
            pps.withUnsafeBytes { rawBufferPointer in
                guard let ppsPointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    print("Error obtaining pointer to PPS.")
                    return
                }
                
                let pointers: [UnsafePointer<UInt8>] = [spsPointer, ppsPointer]
                var formatDescription: CMFormatDescription?
                
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                                  parameterSetCount: 2,
                                                                                  parameterSetPointers: pointers,
                                                                                  parameterSetSizes: parameterSetSizes,
                                                                                  nalUnitHeaderLength: 4,
                                                                                  formatDescriptionOut: &formatDescription)
                
                if status == noErr, let formatDescription = formatDescription {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                    print("Breite: \(dimensions.width), Höhe: \(dimensions.height)")

                    let codecType = CMFormatDescriptionGetMediaType(formatDescription)
                    print("Codec-Typ: \(codecType)")
                    
                    self.videoFormatDescription = formatDescription
                    createDecompressionSession()
                } else {
                    print("Fehler beim Erstellen der Videoformatbeschreibung: \(status)")
                }
            }
        }
    }


    
    
    func createDecompressionSession() {
        print("Attempting to create decompression session...")

        // Check if the session already exists and close it if necessary
        if decompressionSession != nil {
            print("Decompression session already exists, invalidating and setting to nil.")
            VTDecompressionSessionInvalidate(decompressionSession!)
            decompressionSession = nil
        }

        // Ensure videoFormatDescription is set
        guard let videoFormatDescription = self.videoFormatDescription else {
            print("VideoFormatDescription is nil, can't create decompression session.")
            return
        }
        print("VideoFormatDescription is set, proceeding with decompression session creation.")

        let parameters = NSMutableDictionary()

        let callback: VTDecompressionOutputCallback = { decompressionOutputRefCon, _, status, _, imageBuffer, _, _ in
            let mySelf = Unmanaged<ImageDataHandler>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()

            guard status == noErr, let imageBuffer = imageBuffer else {
                print("Error in decompression callback: \(status)")
                return
            }

            // Convert CVPixelBuffer to UIImage
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("NewImageReceived"), object: nil, userInfo: ["port": mySelf.port, "image": uiImage])
            }
        }

        var callbackRecord = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: callback,
                                                                 decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())

        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: videoFormatDescription, decoderSpecification: parameters, imageBufferAttributes: nil, outputCallback: &callbackRecord, decompressionSessionOut: &decompressionSession)

        if status == noErr {
            print("Decompression session successfully created.")
        } else {
            print("Error creating decompression session: \(status)")
        }
    }


    
}


// MARK: - TCP Image Receiver Logic
class TCPImageReceiver {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    
    // Start TCP server to receive images
    func start(port: Int) throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ImageDataHandler(port: port))
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        self.channel = try bootstrap.bind(host: "localhost", port: port).wait()
        print("Server is running on: \(String(describing: self.channel?.localAddress))")
    }
    
    // Stops the server
    func stop() throws {
        try self.channel?.close().wait()
        try self.group.syncShutdownGracefully()
    }
}

