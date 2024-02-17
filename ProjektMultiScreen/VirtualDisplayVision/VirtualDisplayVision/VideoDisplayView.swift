//
//  VideoDisplayView.swift
//  VirtualDisplayVision
//
//  Created by Quentin Ulmer on 16.02.24.
//
import UIKit
import AVFoundation

class VideoDisplayView: UIView {
    var videoLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        videoLayer.videoGravity = .resizeAspect
        layer.addSublayer(videoLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer.frame = bounds
    }
    
    func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("Self is nil")
                return
            }
            
            // Zusätzliche Überprüfungen und Debugging-Informationen
            let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)
            print("DataBuffer available: \(dataBuffer != nil)")
            
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
            print("Format description available: \(formatDesc != nil)")
            
            if let formatDesc = formatDesc {
                let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                print("Media type: \(mediaType)")
            }
            
            let hasImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) != nil
            print("Has image buffer: \(hasImageBuffer)")
            
            // Überprüfe, ob videoLayer bereit ist
            if self.videoLayer.isReadyForMoreMediaData {
                // Vorhandene Debugging-Informationen
                print("sampleBuffer data type: \(CFGetTypeID(sampleBuffer))")
                print("sampleBuffer duration: \(CMSampleBufferGetDuration(sampleBuffer))")
                print("sampleBuffer isValid: \(CMSampleBufferIsValid(sampleBuffer))")
                print("sampleBuffer total size: \(CMSampleBufferGetTotalSampleSize(sampleBuffer))")
                
                // Einreihen des sampleBuffer in videoLayer
                self.videoLayer.enqueue(sampleBuffer)
                print("Sample buffer enqueued")
            } else {
                print("Video Layer is not ready for more data")
            }
        }
    }

}
