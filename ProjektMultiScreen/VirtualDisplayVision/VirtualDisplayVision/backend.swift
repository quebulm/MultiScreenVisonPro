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

// Recive and Handle Data
final class ImageDataHandler: ChannelInboundHandler {
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

            // Check if Iamge is Complete
            let imageDataSeparator = "END_OF_IMAGE".data(using: .utf8)!
            if dataHasSuffix(data: receivedData, suffix: imageDataSeparator) {
                let imageEndIndex = receivedData.endIndex - imageDataSeparator.count
                
                let imageData = receivedData[..<imageEndIndex]
                if let image = UIImage(data: imageData) {
                    DispatchQueue.main.async {
                        // store Iamge and Port
                        let userInfo = ["image": image, "port": self.port] as [String : Any]
                        
                        // Send userInfo Dictionary
                        NotificationCenter.default.post(name: NSNotification.Name("NewImageReceived"), object: nil, userInfo: userInfo)
                    }
                }
                    
                    let confirmationMessage = "Image received successfully."
                    var buffer = context.channel.allocator.buffer(capacity: confirmationMessage.utf8.count)
                    buffer.writeString(confirmationMessage)
                    context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)

                    // Remove Processed Subrange
                    receivedData.removeSubrange(..<imageEndIndex)

                    // Remove imageDataSeparator
                    receivedData.removeFirst(imageDataSeparator.count)
                } else {
                    print("Fehler: Konnte das Bild nicht erstellen.")
                }
            }
        }
    
    
    
    func dataHasSuffix(data: Data, suffix: Data) -> Bool {
        guard data.count >= suffix.count else { return false }
        let dataEndRange = data.index(data.endIndex, offsetBy: -suffix.count)..<data.endIndex
        return data[dataEndRange] == suffix
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
