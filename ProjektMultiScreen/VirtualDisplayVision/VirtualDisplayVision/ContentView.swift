import SwiftUI
import CoreMedia

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @StateObject private var viewModel = VideoStreamViewModel()
    
    
    var body: some View {
            VStack {
                VideoDisplaySwiftUIView(viewModel: viewModel)
                    .frame(width: 400, height: 300)
                
                Spacer()
                
                Text("TCP Video Stream")
                    .padding(.bottom, 50)
                
                Button("Start Listening on Default Port") {
                    viewModel.startListening(on: viewModel.port)
                }
            }
        }
    }

class VideoStreamViewModel: ObservableObject, ImageDataHandlerDelegate {
    
    func didReceiveSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        print("didReceiveSampleBuffer called")
        DispatchQueue.main.async {
            // Handle sample buffer received
            self.currentSampleBuffer = sampleBuffer
        }
    }
    
    func getImageDataHandler() -> ImageDataHandler? {
        return self.imageDataHandler
    }
    
    init() {
        print("VideoStreamViewModel initialised")
        imageDataHandler = ImageDataHandler(port: port)
        imageDataHandler?.delegate = self
        print("ImageDataHandler \(imageDataHandler), delegate \(imageDataHandler?.delegate)")
    }
    
    @Published var currentSampleBuffer: CMSampleBuffer?
    var port: Int = 8000
    private var imageDataHandler: ImageDataHandler? // Owns ImageDataHandler

    func startListening(on port: Int) {
        let imageReceiver = TCPImageReceiver()

        do {
            try imageReceiver.start(port: port, withHandler: self.imageDataHandler!)
            print("Server started on port \(port)...")
           
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

