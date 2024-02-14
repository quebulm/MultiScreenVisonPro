import SwiftUI

struct TabBarView: View {
    var startListeningAction: () -> Void
    var openNewSpaceAction: () -> Void

    var body: some View {
        HStack {
            Button(action: startListeningAction) {
                Label("Start", systemImage: "play.circle")
            }
            Button(action: openNewSpaceAction) {
                Label("New Space", systemImage: "square.grid.2x2")
            }
        }
        .padding()
    }
}




struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    var port = 8000
    @StateObject private var viewModel = VideoStreamViewModel(port: 8000)
    
    var body: some View {
        ZStack {
            // Main content area
            VStack {
                if let image = viewModel.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    Text("Waiting for video...")
                        .padding()
                }
            }
            
            // Positions the TabBarView bottom right
            HStack {
                Spacer() // Shifts everything to the right
                VStack {
                    Spacer() // Shifts everything downwards
                    TabBarView(
                        startListeningAction: {
                            viewModel.startListening(on: viewModel.port)
                        },
                        openNewSpaceAction: {
                            Task {
                                openWindow(id: "SecondWindow")
                            }
                        }
                    )
                    .frame(width: 500)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



struct SecondWindow: View {
    @Environment(\.openWindow) private var openWindow
    var port = 8001
    @StateObject private var viewModel = VideoStreamViewModel(port: 8001)
    
    var body: some View {
        ZStack {
            // Main content area
            VStack {
                if let image = viewModel.currentFrame2 {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    Text("Waiting for video...")
                        .padding()
                }
            }
            

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    TabBarView(
                        startListeningAction: {
                            viewModel.startListening(on: viewModel.port)
                        },
                        openNewSpaceAction: {
                            Task {
                                openWindow(id: "thirdWindow")
                            }
                        }
                    )
                    .frame(width: 500)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SecondWindow()
}

struct thirdWindow: View {
    @Environment(\.openWindow) private var openWindow
    var port = 8002
    @StateObject private var viewModel = VideoStreamViewModel(port: 8002)
    
    var body: some View {
        ZStack {
            VStack {
                if let image = viewModel.currentFrame3 {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    Text("Waiting for video...")
                        .padding()
                }
            }
            
            
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    TabBarView(
                        startListeningAction: {
                            viewModel.startListening(on: viewModel.port)
                        },
                        openNewSpaceAction: {
                            Task {
                                // Too much lag
                            }
                        }
                    )
                    .frame(width: 500)
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    thirdWindow()
}


class VideoStreamViewModel: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var currentFrame2: UIImage?
    @Published var currentFrame3: UIImage?

    private var imageReceivers: [TCPImageReceiver] = []
    var port: Int
    
    init(port: Int) {
        self.port = port
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NewImageReceived"), object: nil, queue: .main) { [weak self] notification in
            // Extrahiere userInfo aus der Notification
            guard let userInfo = notification.userInfo,
                  let receivedPort = userInfo["port"] as? Int,
                  let image = userInfo["image"] as? UIImage else {
                return
            }
            
            // Decide which variable gets updated depending on the received port
            if receivedPort == 8000 {
                self?.currentFrame = image
            } else if receivedPort == 8001 {
                self?.currentFrame2 = image
            } else if receivedPort == 8002 {
                self?.currentFrame3 = image
            }
        }
    }
    
    func startListening(on port: Int) {
        let imageReceiver = TCPImageReceiver()

        do {
            try imageReceiver.start(port: port)
            print("Server started on port \(port)...")
            self.imageReceivers.append(imageReceiver)
        } catch {
            print("Server could not be started on Port \(port): \(error)")
        }
    }
}


@available(iOS 13.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

