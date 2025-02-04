import AVFoundation
import CoreImage
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

@MainActor
class CreateExerciseViewModel: NSObject, ObservableObject,
  AVCaptureVideoDataOutputSampleBufferDelegate
{
  @Published var exercise = Exercise.empty()
  @Published var videoThumbnail: UIImage?
  @Published var showError = false
  @Published var errorMessage = ""
  @Published var isUploading = false
  @Published var videoData: Data?
  @Published var isRecording = false
  @Published var showCamera = false
  @Published var currentFrame: CGImage?

  // Camera session properties
  var captureSession: AVCaptureSession?
  var videoOutput: AVCaptureMovieFileOutput?
  private var deviceInput: AVCaptureDeviceInput?
  private var temporaryRecordingURL: URL?
  private var recordingDelegate = VideoRecordingDelegate()
  private var sessionQueue = DispatchQueue(label: "video.preview.session")
  private var addToPreviewStream: ((CGImage) -> Void)?

  lazy var previewStream: AsyncStream<CGImage> = {
    AsyncStream { continuation in
      addToPreviewStream = { cgImage in
        continuation.yield(cgImage)
      }
    }
  }()

  override init() {
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
        await self?.processRecordedVideo(at: url)
        self?.showCamera = false
      }
    }

    Task {
      await handleCameraPreviews()
    }
  }

  func handleCameraPreviews() async {
    for await image in previewStream {
      currentFrame = image
    }
  }

  var canUpload: Bool {
    !exercise.title.isEmpty && !exercise.description.isEmpty && videoData != nil
      && !exercise.targetMuscles.isEmpty && exercise.duration > 0
  }

  func loadVideo(from item: PhotosPickerItem?) async {
    guard let item = item else { return }

    do {
      let movieData = try await item.loadTransferable(type: Data.self)
      self.videoData = movieData

      // Generate thumbnail
      if let movieData = movieData {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(
          UUID().uuidString + ".mov")
        try movieData.write(to: tmpURL)

        let asset = AVAsset(url: tmpURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
        self.videoThumbnail = UIImage(cgImage: cgImage)

        // Get video duration
        let duration = try await asset.load(.duration)
        self.exercise.duration = Int(duration.seconds)

        try FileManager.default.removeItem(at: tmpURL)
      }
    } catch {
      showError = true
      errorMessage = "Failed to load video: \(error.localizedDescription)"
    }
  }

  func uploadExercise() async {
    guard let uploadData = videoData else { return }
    isUploading = true

    do {
      // 1. Upload video to Firebase Storage
      let videoFileName = "\(UUID().uuidString).mp4"
      let videoRef = Storage.storage().reference().child("videos/\(videoFileName)")
      _ = try await videoRef.putDataAsync(uploadData)
      let videoUrl = try await videoRef.downloadURL().absoluteString

      // 2. Upload thumbnail
      if let thumbnailData = videoThumbnail?.jpegData(compressionQuality: 0.7) {
        let thumbnailFileName = "\(UUID().uuidString).jpg"
        let thumbnailRef = Storage.storage().reference().child("thumbnails/\(thumbnailFileName)")
        _ = try await thumbnailRef.putDataAsync(thumbnailData)
        let thumbnailUrl = try await thumbnailRef.downloadURL().absoluteString

        // 3. Update exercise with URLs
        exercise.videoUrl = videoUrl
        exercise.thumbnailUrl = thumbnailUrl

        // 4. Save to Firestore
        let db = Firestore.firestore()
        try await db.collection("videos").document(exercise.id).setData(exercise.dictionary)

        // 5. Reset form
        exercise = Exercise.empty()
        videoData = nil
        videoThumbnail = nil
      }
    } catch {
      showError = true
      errorMessage = "Failed to upload exercise: \(error.localizedDescription)"
    }

    isUploading = false
  }

  // MARK: - Camera Setup

  func setupCamera() {
    Task { @MainActor in
      do {
        let hasPermission = await checkCameraPermission()
        if hasPermission {
          try await configureAndStartCaptureSession()
        } else {
          showError = true
          errorMessage = "Camera access is required. Please enable it in Settings."
          showCamera = false
        }
      } catch {
        showError = true
        errorMessage = "Failed to setup camera: \(error.localizedDescription)"
        showCamera = false
      }
    }
  }

  private func checkCameraPermission() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted:
      return false
    @unknown default:
      return false
    }
  }

  private func configureAndStartCaptureSession() async throws {
    let session = AVCaptureSession()
    session.beginConfiguration()
    session.sessionPreset = .high

    // Add video input
    guard
      let videoDevice = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back)
    else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video device found"])
    }

    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
    guard session.canAddInput(videoInput) else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
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
    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.videoSettings = [
      (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
    ]
    videoOutput.alwaysDiscardsLateVideoFrames = true

    guard session.canAddOutput(videoOutput) else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
    }
    session.addOutput(videoOutput)

    // Configure video connection
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
      if connection.isVideoMirroringSupported {
        connection.isVideoMirrored = false
      }
    }

    // Add movie file output for recording
    let movieOutput = AVCaptureMovieFileOutput()
    guard session.canAddOutput(movieOutput) else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add movie output"])
    }
    session.addOutput(movieOutput)
    self.videoOutput = movieOutput

    session.commitConfiguration()

    // Update properties
    self.captureSession = session

    // Start the session
    sessionQueue.async {
      session.startRunning()
    }
  }

  func startRecording() {
    guard let output = videoOutput else { return }

    // Create temporary URL for recording
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "\(UUID().uuidString).mov"
    temporaryRecordingURL = tempDir.appendingPathComponent(fileName)

    guard let recordingURL = temporaryRecordingURL else { return }

    output.startRecording(to: recordingURL, recordingDelegate: recordingDelegate)
    isRecording = true
  }

  func stopRecording() {
    videoOutput?.stopRecording()
    isRecording = false
  }

  func processRecordedVideo(at url: URL) async {
    do {
      let videoData = try Data(contentsOf: url)
      self.videoData = videoData

      // Generate thumbnail
      let asset = AVAsset(url: url)
      let imageGenerator = AVAssetImageGenerator(asset: asset)
      imageGenerator.appliesPreferredTrackTransform = true

      let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
      self.videoThumbnail = UIImage(cgImage: cgImage)

      // Get video duration
      let duration = try await asset.load(.duration)
      self.exercise.duration = Int(duration.seconds)

      // Clean up temporary file
      try FileManager.default.removeItem(at: url)
      temporaryRecordingURL = nil

    } catch {
      showError = true
      errorMessage = "Failed to process recorded video: \(error.localizedDescription)"
    }
  }

  nonisolated func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext()

    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

    Task { @MainActor in
      self.currentFrame = cgImage
    }
  }
}

// Helper extension to convert Exercise to dictionary
extension Exercise {
  var dictionary: [String: Any] {
    [
      "id": id,
      "type": type,
      "title": title,
      "description": description,
      "instructorId": instructorId,
      "videoUrl": videoUrl,
      "thumbnailUrl": thumbnailUrl,
      "difficulty": difficulty.rawValue,
      "targetMuscles": targetMuscles,
      "duration": duration,
      "sets": sets as Any,
      "reps": reps as Any,
      "createdAt": Timestamp(date: createdAt),
      "updatedAt": Timestamp(date: updatedAt),
    ]
  }
}
