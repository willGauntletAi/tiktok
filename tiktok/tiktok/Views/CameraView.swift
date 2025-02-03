import SwiftUI
import AVFoundation

struct CameraView: View {
    @ObservedObject var viewModel: CreateExerciseViewModel
    
    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Button(action: {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isRecording ? .red : .white)
                                .frame(width: 80, height: 80)
                            
                            if viewModel.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 30, height: 30)
                            } else {
                                Circle()
                                    .stroke(.red, lineWidth: 4)
                                    .frame(width: 70, height: 70)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 30)
            }
            
            VStack {
                HStack {
                    Button(action: { viewModel.showCamera = false }) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            viewModel.setupCaptureSession()
            viewModel.captureSession?.startRunning()
        }
        .onDisappear {
            viewModel.captureSession?.stopRunning()
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        view.backgroundColor = .black
        
        guard let session = session else { return view }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.frame
        }
    }
} 