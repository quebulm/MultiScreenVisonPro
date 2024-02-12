//
//  ContentView.swift
//  VirtualDisplayMac
//
//  Created by Quentin Ulmer on 09.02.24.
//

import SwiftUI


class ContentViewViewModel: ObservableObject {
    // Array, for VirtualDisplayManager-Instance
    @Published var displayManagers: [VirtualDisplayManager] = []
    
    func createVirtualDisplay(id: UInt16) async {
        let displayManager = VirtualDisplayManager()
        
        await displayManager.initializeAndStartStream(id: id)

        DispatchQueue.main.async {
            self.displayManagers.append(displayManager)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewViewModel()
    
    var body: some View {
        VStack {
            Button("Create Virtual Display") {
                Task {
                    
                    await viewModel.createVirtualDisplay(id: 8000)
                }
            }
            Button("Create Virtual Display2") {
                Task {
                    await viewModel.createVirtualDisplay(id: 8001)
                }
            }
            Button("Create Virtual Display3") {
                Task {
                    await viewModel.createVirtualDisplay(id: 8002)
                }
            }
            .padding()
            .buttonStyle(.bordered)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
