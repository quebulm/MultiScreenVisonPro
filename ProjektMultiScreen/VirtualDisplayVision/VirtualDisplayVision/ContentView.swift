import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var port = 8000
    @StateObject private var viewModel = VideoStreamViewModel(port: 8000)
    
    var body: some View {
        VStack {
            if let image = viewModel.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                Text("Warte auf Video...")
                    .padding()
            }
            
            Spacer()
            
            Text("TCP Video Stream")
                .padding(.bottom, 50)
            
            Button("Start Listening on Default Port") {
                viewModel.startListening(on: viewModel.port)
            }
            
            Button("Öffne neues Space für nächsten Port") {
                Task {
                    openWindow(id: "SecondWindow")
                }
            }
        }
    }
}

struct SecondWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var port = 8001
    @StateObject private var viewModel = VideoStreamViewModel(port: 8001)
    
    var body: some View {
        VStack {
            if let image = viewModel.currentFrame2 {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                Text("Warte auf Video...")
                    .padding()
            }
            
            Spacer()
            
            Text("TCP Video Stream")
                .padding(.bottom, 50)
            
            Button("Start Listening on Default Port") {
                viewModel.startListening(on: viewModel.port)
            }
            
            Button("Öffne neues Space für nächsten Port") {
                Task {
                    viewModel.startListening(on: port)
                    openWindow(id: "thirdWindow")
                }
            }
        }
    }
   }

#Preview {
    SecondWindow()
}

struct thirdWindow: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    var port = 8002
    @StateObject private var viewModel = VideoStreamViewModel(port: 8002)
    
    var body: some View {
        VStack {
            if let image = viewModel.currentFrame3 {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                Text("Warte auf Video...")
                    .padding()
            }
            
            Spacer()
            
            Text("TCP Video Stream")
                .padding(.bottom, 50)
            
            Button("Start Listening on Default Port") {
                viewModel.startListening(on: viewModel.port)
            }
        
        }
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
            
            // Entscheide, welche Variable aktualisiert wird, abhängig vom empfangenen Port
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
            print("Server gestartet auf Port \(port)...")
            self.imageReceivers.append(imageReceiver)
        } catch {
            print("Server konnte nicht gestartet werden auf Port \(port): \(error)")
        }
    }
}


@available(iOS 13.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

