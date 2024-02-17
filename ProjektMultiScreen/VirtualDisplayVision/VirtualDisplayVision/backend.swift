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

final class ImageDataHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private var receivedData = Data()
    private let receivedDataLock = DispatchQueue(label: "receivedData.access") // thread-safe
    var port: Int
    
    init(port: Int) {
        self.port = port
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = self.unwrapInboundIn(data)
        
        if let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) {
            receivedDataLock.async(flags: .barrier) {
                self.receivedData.append(contentsOf: bytes)
                
                self.checkAndProcessImage(context: context)
            }
        }
    }
    
    private func checkAndProcessImage(context: ChannelHandlerContext) {
        let imageDataSeparator = "END_OF_IMAGE".data(using: .utf8)!
        if let separatorRange = receivedData.range(of: imageDataSeparator, options: .backwards) {
            let imageEndIndex = separatorRange.lowerBound
            
            let imageData = receivedData[..<imageEndIndex]
            if let image = UIImage(data: imageData) {
                DispatchQueue.main.async {
                    let userInfo = ["image": image, "port": self.port] as [String: Any]
                    NotificationCenter.default.post(name: NSNotification.Name("NewImageReceived"), object: nil, userInfo: userInfo)
                }
            } else {
                DispatchQueue.main.async {
                    print("Error: Could not create the image.")
                }
            }
            
            self.receivedData.removeSubrange(..<separatorRange.upperBound)
            
            // check for Data overflow
            if self.receivedData.count > 60_000_000 { // 60 MB
                self.receivedData = Data() // reset receivedData
                print("Warning: Received data reset due to size overflow.")
            }
        }
    }
}

class TCPImageReceiver {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    func start(port: Int) throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ImageDataHandler(port: port))
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: "localhost", port: port).wait()
        print("The server is running on: \(channel!.localAddress!)")
    }

    func stop() throws {
        try self.channel?.close().wait()
        try self.group.syncShutdownGracefully()
    }
}
