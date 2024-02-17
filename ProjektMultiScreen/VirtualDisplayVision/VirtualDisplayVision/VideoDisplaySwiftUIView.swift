//
//  VideoDisplaySwiftUIView.swift
//  VirtualDisplayVision
//
//  Created by Quentin Ulmer on 16.02.24.
//
import SwiftUI
import UIKit
import CoreMedia
import SwiftUI

struct VideoDisplaySwiftUIView: UIViewRepresentable {
    @ObservedObject var viewModel: VideoStreamViewModel

    func makeUIView(context: Context) -> VideoDisplayView {
        VideoDisplayView()
    }
    
    func updateUIView(_ uiView: VideoDisplayView, context: Context) {
        if let sampleBuffer = viewModel.currentSampleBuffer {
            print("UI aktualisiert")
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video {
                // Verarbeite den SampleBuffer, der Videodaten enthält
                uiView.displaySampleBuffer(sampleBuffer)
            } else {
                print("audio ")
            }

        }
    }
}


