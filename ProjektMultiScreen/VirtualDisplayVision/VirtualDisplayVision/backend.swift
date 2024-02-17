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

protocol ImageDataHandlerDelegate: AnyObject {
    func didReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer)
}


// MARK: - ChannelInboundHandler for processing received data
final class ImageDataHandler: ChannelInboundHandler {
    weak var delegate: ImageDataHandlerDelegate?
    var videoFormatDescription: CMVideoFormatDescription?
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    var videoLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    weak var videoDisplayView: VideoDisplayView?

    
    
    var framessend: Int64 = 0
    
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
                framessend += 1
                print("sended: \(framessend)")
                self.processVideoFrame(nalUnit: nalUnit)
            }
        }
    }
    
    
    func rollingHashSearch(in buffer: Data, from index: Data.Index) -> Range<Data.Index>? {
        let targetSlice = Data([0x00, 0x00, 0x00, 0x01])
        let targetLength = targetSlice.count
        guard buffer.count >= index + targetLength else { return nil }
        
        var currentHash = 0
        var targetHash = 0
        for byte in targetSlice {
            targetHash += Int(byte)
        }
        
        for i in 0..<targetLength {
            currentHash += Int(buffer[index + i])
        }
        
        if currentHash == targetHash && buffer[index..<(index + targetLength)] == targetSlice {
            return index..<(index + targetLength)
        }
        
        for i in index..<(buffer.count - targetLength) {
            currentHash -= Int(buffer[i])
            currentHash += Int(buffer[i + targetLength])
            
            if currentHash == targetHash {
                let potentialMatchRange = (i + 1)..<(i + 1 + targetLength)
                if buffer[potentialMatchRange] == targetSlice {
                    return potentialMatchRange
                }
            }
        }
        
        return nil
    }
    
    
    
    func extractCompleteNALUnit(from buffer: inout Data) -> Data? {
        guard let firstStartCodeRange = rollingHashSearch(in: buffer, from: buffer.startIndex) else {
            return nil
        }
        
        let nextSearchStartIndex = firstStartCodeRange.upperBound
        guard let secondStartCodeRange = rollingHashSearch(in: buffer, from: nextSearchStartIndex) else {
            return nil
        }
        
        let nalUnitRange = firstStartCodeRange.upperBound..<secondStartCodeRange.lowerBound
        if nalUnitRange.lowerBound >= buffer.startIndex && nalUnitRange.upperBound <= buffer.endIndex {
            let nalUnit = buffer.subdata(in: nalUnitRange)
            buffer.removeSubrange(0..<secondStartCodeRange.lowerBound)
            print("NalUnit Processed")
            return nalUnit
        } else {
            return nil
        }
    }
    
    
    
    func annexBtoLengthPrefixed(nalUnit: Data) -> Data {
        var length = UInt32(nalUnit.count).bigEndian // length in big endian
        let lengthData = Data(bytes: &length, count: 4)
        
        var lengthPrefixedNalUnit = Data()
        lengthPrefixedNalUnit.append(lengthData)
        lengthPrefixedNalUnit.append(nalUnit)
        
        return lengthPrefixedNalUnit
    }
    
    func processVideoFrame(nalUnit: Data) -> Bool {
        
        // Extract the NAL unit type
        let nalUnitType = nalUnit.first! & 0x1F
        print("NAL Unit Type: \(nalUnitType)")
        
        switch nalUnitType {
        case 7:
            // Sequence Parameter Set (SPS)
            spsData = nalUnit
        case 8:
            // Picture Parameter Set (PPS)
            ppsData = nalUnit
        case 1, 5:
            // Coded Slice of a Non-IDR Picture oder Coded Slice of an IDR Picture
            // Main Video Data
            let lengthPrefixedNalUnit = annexBtoLengthPrefixed(nalUnit: nalUnit)
            guard let _ = spsData, let _ = ppsData else {
                print("SPS or PPS data not available.")
                return false
            }
            
            guard videoFormatDescription != nil else {
                print("Video format description not available.")
                prepareVideoFormatDescription()
                return false
            }
            
            guard let sampleBuffer = createCMSampleBufferFromNALUnit(nalUnit: lengthPrefixedNalUnit) else {
                print("Failed to create sample buffer.")
                return false
            }
            
            DispatchQueue.main.async { [weak self] in
                print("called didReceiveSampleBuffer, delegate is \(String(describing: self?.delegate))")
                self?.delegate?.didReceiveSampleBuffer(sampleBuffer)
                return
            }
            
        default:
            print("Unhandled NAL Unit Type: \(nalUnitType)")
            return false
        }
        
        return true
    }
    
//    func displayWithAVSampleBufferDisplayLayer(sampleBuffer: CMSampleBuffer) -> Bool {
//            DispatchQueue.main.async { [weak self] in
//                guard let self = self, let layer = self.videoDisplayView?.videoLayer, layer.isReadyForMoreMediaData else {
//                    print("Layer is not ready for more media data.")
//                    return
//                }
//                layer.enqueue(sampleBuffer)
//            }
//            return true
//        }

    
    
    
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
                } else {
                    print("Fehler beim Erstellen der Videoformatbeschreibung: \(status)")
                }
            }
        }
    }
}

// MARK: - TCP Image Receiver Logic
class TCPImageReceiver {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    
    // Start TCP server to receive images
    func start(port: Int, withHandler handler: ImageDataHandler) throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(handler)
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

