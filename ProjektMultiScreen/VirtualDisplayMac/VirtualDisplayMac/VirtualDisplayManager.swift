//
//  VirtualDisplayManager.swift
//  VirtualDisplayMac
//
//  Created by Quentin Ulmer on 09.02.24.
//

//import Foundation
//import CoreGraphics
//import AVFoundation
//import ScreenCaptureKit

import Foundation
import ScreenCaptureKit
import NIO
import NIOFoundationCompat


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
                
                streamConfig.width = virtualDisplay.width // Example, adjust based on actual requirements
                streamConfig.height = virtualDisplay.height // Example, adjust based on actual requirements
                // Set the capture interval at 60 fps.
                streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                // Increase the depth of the frame queue to ensure high fps at the expense of increasing
                // the memory footprint of WindowServer.
                streamConfig.queueDepth = 5
                
                // Initialize and start the stream with general content and configuration
                let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
                // Erstelle eine Dispatch Queue für die Verarbeitung der Sample Buffers
                let videoSampleBufferQueue = DispatchQueue(label: "com.example.myApp.videoSampleBufferQueue")

                // Erstelle eine Instanz von StreamOutput
                let streamOutput = StreamOutput(sampleHandlerQueue: videoSampleBufferQueue)
                
                streamOutput.setupTCPConnection(to: "localhost", port: id)

                // Füge StreamOutput dem SCStream hinzu
                try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoSampleBufferQueue)

                self.displayStream = stream // Store the stream instance to keep it alive
                self.streamOutput = streamOutput
                try await stream.startCapture()
                
//                // Initialize and start the stream with the filter and configuration
//                try await SCStream(filter: filter, configuration: streamConfig, delegate: self).startCapture()
                
            } else {
                print("Failed to find a matching display for the given virtualDisplay.id")
            }
        } catch {
            print("Failed to start screen capture: \(error.localizedDescription)")
        }
    }
    
}


class StreamOutput: NSObject,SCStreamOutput {
    
    let sampleHandlerQueue: DispatchQueue
    var channel: Channel?
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    private let context: CIContext


    init(sampleHandlerQueue: DispatchQueue) {
            self.context = CIContext()
            self.sampleHandlerQueue = sampleHandlerQueue
        }
    
    deinit {
            // Räume die EventLoopGroup auf, wenn StreamOutput zerstört wird
            try? eventLoopGroup.syncShutdownGracefully()
        }

    
    func setupTCPConnection(to ipAddress: String, port: UInt16) {
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                // Konfiguriere den Bootstrap (z.B. Timeout, ChannelOptionen)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    // Hier könntest du Handler hinzufügen, falls du Nachrichten verarbeiten möchtest,
                    // die vom Server empfangen werden
                    return channel.eventLoop.makeSucceededFuture(())
                }
            bootstrap.connect(host: ipAddress, port: Int(port)).whenSuccess { channel in
                print("Verbunden mit \(ipAddress):\(port)")
                self.channel = channel
            }
        }

    func sendTCP(data: Data) {
        guard let channel = self.channel else {
            print("TCP-Verbindung ist nicht hergestellt.")
            return
        }

        let imageDataSeparator = "END_OF_IMAGE".data(using: .utf8)!
        var sendData = data
        sendData.append(imageDataSeparator)

        var buffer = channel.allocator.buffer(capacity: sendData.count)
        buffer.writeBytes(sendData)
        channel.writeAndFlush(buffer).whenComplete { result in
            switch result {
            case .success:
                print("erfolgreich gesendet.")
            case .failure(let error):
                print("Fehler beim Senden: \(error)")
                break // Optional: Abbruch bei Fehler
            }
        }
    }

    
    func processFrameAndSendTCP(_ sampleBuffer: CMSampleBuffer) {
        print("entered processFrameAndSendTCP")
        guard let data = convertSampleBufferToData(sampleBuffer) else {
            print("Failed to convert sample buffer to data")
            return
        }

        sendTCP(data: data)
    }
    
    // Konvertierung von CMSampleBuffer zu Data
    func convertSampleBufferToData(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Fehler: Konnte keinen ImageBuffer aus dem SampleBuffer extrahieren.")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        // Optionen für die JPEG-Komprimierung, inklusive Bildqualität.
        let jpegCompressionQuality: CGFloat = 0.8
        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegCompressionQuality]
        
        // Direkte Verwendung von CGColorSpaceCreateDeviceRGB(), da es nicht optional ist.
        let colorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // Verwendung von guard für die optionale Rückgabe von jpegRepresentation().
        guard let jpegData = self.context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) else {
            print("Fehler: Konnte das CIImage nicht als JPEG komprimieren.")
            return nil
        }
        
        return jpegData
    }
 

    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Verarbeite den SampleBuffer hier, um ihn über TCP zu senden
        processFrameAndSendTCP(sampleBuffer)
    }
}


