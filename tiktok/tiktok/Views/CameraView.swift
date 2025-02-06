import AVFoundation
import SwiftUI

struct CameraView: View {
  @ObservedObject var viewModel: CreateExerciseViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      if let frame = viewModel.currentFrame {
        GeometryReader { geometry in
          Image(decorative: frame, scale: 1.0)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .id(frame)
        }
        .ignoresSafeArea()
      }

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
          .disabled(viewModel.captureSession == nil)

          Spacer()
        }
        .padding(.bottom, 30)
      }

      VStack {
        HStack {
          Button(action: {
            viewModel.captureSession?.stopRunning()
            viewModel.showCamera = false
            dismiss()
          }) {
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
      Task {
        await viewModel.setupCamera()
      }
    }
    .onDisappear {
      viewModel.captureSession?.stopRunning()
    }
    .alert(
      "Camera Error",
      isPresented: Binding(
        get: { viewModel.showError },
        set: { viewModel.showError = $0 }
      )
    ) {
      Button("OK") {
        dismiss()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}

struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession?

  func makeUIView(context: Context) -> PreviewView {
    print("Creating camera preview view")
    let view = PreviewView()
    view.backgroundColor = .black

    guard let session = session else {
      print("No capture session available")
      return view
    }

    print("Configuring preview layer with session")
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill

    return view
  }

  func updateUIView(_ uiView: PreviewView, context: Context) {
    print("Updating camera preview view")
    if let session = session {
      if uiView.previewLayer.session !== session {
        print("Updating preview layer session")
        uiView.previewLayer.session = session
      }
    }
  }
}

extension CameraPreviewView {
  class PreviewView: UIView {
    override class var layerClass: AnyClass {
      return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
      return layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      print("Layout subviews - bounds: \(bounds)")
      previewLayer.frame = bounds
      previewLayer.connection?.videoOrientation = .portrait

      // Add additional configuration
      previewLayer.cornerRadius = 0
      previewLayer.masksToBounds = true

      if let connection = previewLayer.connection {
        print(
          "Preview layer connection available - orientation: \(connection.videoOrientation.rawValue)"
        )
      } else {
        print("No preview layer connection")
      }
    }
  }
}
