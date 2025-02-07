import AVFoundation
import SwiftUI
import VideoToolbox

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.dismiss) private var dismiss
    var onVideoRecorded: ((URL) -> Void)?

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
                HStack {
                    Button(action: {
                        viewModel.captureSession?.stopRunning()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            await viewModel.switchCamera()
                        }
                    }) {
                        Image(systemName: "camera.rotate")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .disabled(viewModel.isRecording)
                }
                Spacer()
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
        }
        .onAppear {
            Task {
                viewModel.onVideoRecorded = onVideoRecorded
                viewModel.dismiss = { [dismiss] in
                    dismiss()
                }
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

@MainActor
class CameraViewModel: NSObject, ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var isRecording = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back

    private var _captureSession: AVCaptureSession?
    var captureSession: AVCaptureSession? {
        get { _captureSession }
        set { _captureSession = newValue }
    }

    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var recordingDelegate = VideoRecordingDelegate()
    private var sessionQueue = DispatchQueue(label: "video.preview.session")
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated)

    private let frameHandler: FrameHandler

    lazy var previewStream: AsyncStream<CGImage> = AsyncStream { [weak self] continuation in
        Task {
            await self?.frameHandler.setFrameHandler { cgImage in
                Task { @MainActor [weak self] in
                    self?.currentFrame = cgImage
                }
                continuation.yield(cgImage)
            }
        }
    }

    override init() {
        frameHandler = FrameHandler()
        super.init()
        recordingDelegate.onFinishRecording = { [weak self] url, error in
            if let error = error {
                Task { @MainActor in
                    self?.showError = true
                    self?.errorMessage = "Recording failed: \(error.localizedDescription)"
                }
                return
            }

            Task { @MainActor in
                self?.isRecording = false
                self?.onVideoRecorded?(url)
                self?.dismiss?()
            }
        }

        Task {
            await handleCameraPreviews()
        }
    }

    var onVideoRecorded: ((URL) -> Void)?
    var dismiss: (() -> Void)?

    func handleCameraPreviews() async {
        for await image in previewStream {
            currentFrame = image
        }
    }

    func setupCamera() async {
        do {
            try await configureAndStartCaptureSession()
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }

    func configureAndStartCaptureSession() async throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video device found"])
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        session.addInput(videoInput)
        deviceInput = videoInput

        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        // Add video preview output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(videoOutput) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        session.addOutput(videoOutput)
        videoDataOutput = videoOutput

        // Configure video connection
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90.0) {
                connection.videoRotationAngle = 90.0 // Portrait mode
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }

        // Add movie file output for recording
        let movieOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(movieOutput) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add movie output"])
        }
        session.addOutput(movieOutput)
        self.videoOutput = movieOutput

        session.commitConfiguration()

        // Start the session on a background queue
        Task.detached {
            session.startRunning()
        }

        await MainActor.run {
            self._captureSession = session
        }
    }

    func startRecording() {
        guard let output = videoOutput else { return }

        // Create temporary URL for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).mov"
        let recordingURL = tempDir.appendingPathComponent(fileName)

        output.startRecording(to: recordingURL, recordingDelegate: recordingDelegate)
        isRecording = true
    }

    func stopRecording() {
        videoOutput?.stopRecording()
    }

    func switchCamera() async {
        guard let session = captureSession else { return }

        // Don't allow switching while recording
        guard !isRecording else { return }

        session.beginConfiguration()

        // Remove existing input
        if let currentInput = deviceInput {
            session.removeInput(currentInput)
        }

        do {
            // Get new camera position
            let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back

            // Get new camera device
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get camera device"])
            }

            // Create and add new input
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(videoInput) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }

            session.addInput(videoInput)
            deviceInput = videoInput
            currentCameraPosition = newPosition

            // Update video connection for front camera mirroring
            if let connection = videoDataOutput?.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (newPosition == .front)
                }
                if connection.isVideoRotationAngleSupported(90.0) {
                    connection.videoRotationAngle = 90.0
                }
            }

            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            showError = true
            errorMessage = "Failed to switch camera: \(error.localizedDescription)"
        }
    }
}

// MARK: - Frame Handler

actor FrameHandler {
    private var onFrame: ((CGImage) -> Void)?

    func setFrameHandler(_ handler: @escaping (CGImage) -> Void) {
        onFrame = handler
    }

    func handle(_ image: CGImage) {
        onFrame?(image)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        if let cgImage = try? imageBuffer.cgImage() {
            Task {
                await frameHandler.handle(cgImage)
            }
        }
    }
}

extension CVPixelBuffer {
    func cgImage() throws -> CGImage {
        var cgImage: CGImage?
        let options = [kCVPixelBufferCGImageCompatibilityKey: true,
                       kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        VTCreateCGImageFromCVPixelBuffer(self, options: options, imageOut: &cgImage)
        guard let image = cgImage else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        return image
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context _: Context) -> PreviewView {
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

    func updateUIView(_ uiView: PreviewView, context _: Context) {
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

            if previewLayer.connection?.isVideoRotationAngleSupported(90.0) == true {
                previewLayer.connection?.videoRotationAngle = 90.0
            }

            previewLayer.cornerRadius = 0
            previewLayer.masksToBounds = true

            if let connection = previewLayer.connection {
                print(
                    "Preview layer connection available - rotation angle: \(connection.videoRotationAngle)"
                )
            } else {
                print("No preview layer connection")
            }
        }
    }
}
