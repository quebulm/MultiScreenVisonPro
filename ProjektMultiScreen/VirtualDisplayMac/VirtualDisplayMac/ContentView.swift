//
//  ContentView.swift
//  VirtualDisplayMac
//
//  Created by Quentin Ulmer on 09.02.24.
//

import SwiftUI


class ContentViewViewModel: ObservableObject {
    // Array, das die VirtualDisplayManager-Instanzen speichert
    @Published var displayManagers: [VirtualDisplayManager] = []
    
    func createVirtualDisplay(id: UInt16) async {
        // Erstelle eine neue Instanz von VirtualDisplayManager
        let displayManager = VirtualDisplayManager()
        // Initialisiere und starte den Stream für dieses Display
        await displayManager.initializeAndStartStream(id: id)
        // Füge den neuen VirtualDisplayManager unserem Array hinzu, um ihn zu erhalten
        DispatchQueue.main.async {
            self.displayManagers.append(displayManager)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewViewModel()
    
    var body: some View {
        VStack {
            // Dein bisheriger Code
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
