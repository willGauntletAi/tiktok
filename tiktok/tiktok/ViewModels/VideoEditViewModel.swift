import AVFoundation
import SwiftUI
import UIKit

@MainActor
class VideoEditViewModel: ObservableObject {
  @Published var videoAsset: AVAsset?
  @Published var videoThumbnail: UIImage?
  @Published var isProcessing = false
  @Published var errorMessage: String?
  @Published var duration: Double = 0
  @Published var startTime: Double = 0 {
    didSet { updatePlayerTime() }
  }
  @Published var endTime: Double = 0 {
    didSet { updatePlayerTime() }
  }

  // Video editing properties
  @Published var brightness: Double = 0 {
    didSet { updatePlayerItem() }
  }
  @Published var contrast: Double = 1 {
    didSet { updatePlayerItem() }
  }
  @Published var saturation: Double = 1 {
    didSet { updatePlayerItem() }
  }
  @Published var volume: Double = 1 {
    didSet { updatePlayerVolume() }
  }

  private var player: AVPlayer?
  private var playerItem: AVPlayerItem?
  private var timeObserver: Any?
  private var videoTrack: AVAssetTrack?

  func loadVideo(from url: URL) async {
    isProcessing = true
    do {
      let asset = AVAsset(url: url)
      self.videoAsset = asset

      // Get video duration
      let duration = try await asset.load(.duration)
      self.duration = duration.seconds
      self.endTime = duration.seconds

      // Generate thumbnail
      let imageGenerator = AVAssetImageGenerator(asset: asset)
      imageGenerator.appliesPreferredTrackTransform = true
      let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
      self.videoThumbnail = UIImage(cgImage: cgImage)

      // Setup player with initial composition
      try await setupPlayer(with: asset)

    } catch {
      errorMessage = "Failed to load video: \(error.localizedDescription)"
    }
    isProcessing = false
  }

  private func setupPlayer(with asset: AVAsset) async throws {
    // Remove existing time observer
    if let timeObserver = timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }

    // Load video track
    let tracks = try await asset.loadTracks(withMediaType: .video)
    self.videoTrack = tracks.first

    // Create new player item with the asset
    let playerItem = AVPlayerItem(asset: asset)
    self.playerItem = playerItem

    // Create and configure player
    let player = AVPlayer(playerItem: playerItem)
    self.player = player

    // Add time observer
    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      guard let self = self else { return }
      let currentTime = time.seconds
      if currentTime >= self.endTime {
        // Loop back to start time when reaching end time
        // Using @MainActor ensures we're on the main thread
        Task { @MainActor in
          if let player = self.player {
            await player.seek(to: CMTime(seconds: self.startTime, preferredTimescale: 600))
            player.play()
          }
        }
      }
    }

    // Set initial volume and seek to start
    updatePlayerVolume()
    await player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
  }

  private func updatePlayerTime() {
    guard let player = player else { return }
    Task { @MainActor in
      await player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
      player.play()
    }
  }

  private func updatePlayerVolume() {
    player?.volume = Float(volume)
  }

  private func updatePlayerItem() {
    // For now, we'll just update the player item's properties
    // In a more complete implementation, you would apply video filters here
    // using AVVideoComposition and CIFilters
  }

  func getPlayer() -> AVPlayer? {
    return player
  }

  func exportVideo() async throws -> URL {
    guard let asset = videoAsset else {
      throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video loaded"])
    }

    isProcessing = true
    defer { isProcessing = false }

    // Create composition
    let composition = AVMutableComposition()
    let videoComposition = AVMutableVideoComposition()

    // Load tracks
    let tracks = try await (
      video: asset.loadTracks(withMediaType: .video).first,
      audio: asset.loadTracks(withMediaType: .audio).first
    )

    guard let videoTrack = tracks.video,
      let audioTrack = tracks.audio
    else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load video tracks"])
    }

    // Create composition tracks
    guard
      let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid),
      let compositionAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw NSError(
        domain: "", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create composition tracks"])
    }

    // Set time range
    let timeRange = CMTimeRange(
      start: CMTime(seconds: startTime, preferredTimescale: 600),
      end: CMTime(seconds: endTime, preferredTimescale: 600))

    do {
      // Add video and audio tracks to composition
      try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
      try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)

      // Get the video track's preferred transform
      let originalTransform = try await videoTrack.load(.preferredTransform)

      // Get the video track size
      let naturalSize = try await videoTrack.load(.naturalSize)

      // Determine the correct render size based on the transform
      let isVideoPortrait = originalTransform.a == 0 && abs(originalTransform.b) == 1
      let renderWidth = isVideoPortrait ? naturalSize.height : naturalSize.width
      let renderHeight = isVideoPortrait ? naturalSize.width : naturalSize.height

      // Setup video composition
      videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
      videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

      // Create instruction
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(
        assetTrack: compositionVideoTrack)

      // Apply the original transform to maintain orientation
      layerInstruction.setTransform(originalTransform, at: .zero)

      instruction.layerInstructions = [layerInstruction]
      videoComposition.instructions = [instruction]

      // Create temporary URL for export
      let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(UUID().uuidString).mp4")

      // Setup export session
      guard
        let exportSession = AVAssetExportSession(
          asset: composition,
          presetName: AVAssetExportPresetHighestQuality)
      else {
        throw NSError(
          domain: "", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
      }

      exportSession.outputURL = outputURL
      exportSession.outputFileType = .mp4
      exportSession.videoComposition = videoComposition

      // Set audio mix for volume adjustment
      let audioMix = AVMutableAudioMix()
      let audioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
      audioParameters.setVolume(Float(volume), at: .zero)
      audioMix.inputParameters = [audioParameters]
      exportSession.audioMix = audioMix

      // Export the video
      await exportSession.export()

      if let error = exportSession.error {
        throw error
      }

      return outputURL
    } catch {
      throw error
    }
  }

  func cleanup() {
    if let timeObserver = timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    player?.pause()
    player = nil
    playerItem = nil
    videoAsset = nil
    videoTrack = nil
  }
}

// Custom video compositor for applying filters
class VideoCompositor: NSObject, AVVideoCompositing {
  let renderContext = CIContext()
  let colorSpace = CGColorSpaceCreateDeviceRGB()

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

  func cancelAllPendingVideoCompositionRequests() {}

  var sourcePixelBufferAttributes: [String: Any]? {
    return [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
  }

  var requiredPixelBufferAttributesForRenderContext: [String: Any] {
    return [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
  }

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    guard let sourceBuffer = request.sourceFrame(byTrackID: request.sourceTrackIDs[0].int32Value),
      let instruction = request.videoCompositionInstruction
        as? AVVideoCompositionInstructionProtocol,
      let destinationBuffer = request.renderContext.newPixelBuffer()
    else {
      request.finish(with: NSError(domain: "VideoCompositor", code: -1, userInfo: nil))
      return
    }

    let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)

    // Apply filters here if needed
    let outputImage = sourceImage

    renderContext.render(outputImage, to: destinationBuffer)
    request.finish(withComposedVideoFrame: destinationBuffer)
  }
}
