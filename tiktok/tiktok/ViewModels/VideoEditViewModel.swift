import AVFoundation
import SwiftUI
import UIKit

@MainActor
class VideoEditViewModel: ObservableObject {
    @Published var clips: [VideoClip] = []
    @Published var selectedClipIndex: Int?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var currentPosition: Double = 0
    @Published var duration: Double = 0
    @Published var startTime: Double = 0 {
        didSet { updatePlayerTime() }
    }

    @Published var endTime: Double = 0 {
        didSet { updatePlayerTime() }
    }

    // Current clip editing properties
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

    // Make player accessible to the view
    var player: AVPlayer? {
        _player
    }

    private var _player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var videoTrack: AVAssetTrack?

    var totalDuration: Double {
        clips.reduce(0) { $0 + ($1.endTime - $1.startTime) }
    }

    func addClip(from url: URL) async throws {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let asset = AVAsset(url: url)

            // Get video duration
            let duration = try await asset.load(.duration)

            // Generate thumbnail
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)

            // Create new clip
            var clip = VideoClip(asset: asset, thumbnail: thumbnail)
            clip.endTime = duration.seconds

            // Add to clips array
            clips.append(clip)
            selectedClipIndex = clips.count - 1

            // Setup player with combined clips
            try await setupPlayerWithComposition()

        } catch {
            throw error
        }
    }

    private func setupPlayerWithComposition() async throws {
        // Remove existing time observer
        if let timeObserver = timeObserver {
            _player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        guard !clips.isEmpty else { return }

        // Create composition
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()

        // Create composition tracks
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw NSError(
                domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create composition tracks"]
            )
        }

        var currentTime = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        // Process each clip
        for clip in clips {
            do {
                // Load tracks for current clip
                let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first
                let audioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first

                guard let videoTrack = videoTrack, let audioTrack = audioTrack else { continue }

                // Calculate time range for the clip
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: clip.startTime, preferredTimescale: 600),
                    end: CMTime(seconds: clip.endTime, preferredTimescale: 600)
                )
                let clipDuration = timeRange.duration

                // Insert tracks into composition
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: currentTime)
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: currentTime)

                // Create instruction for this clip
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: currentTime, duration: clipDuration)

                // Get and apply the original transform
                let originalTransform = try await videoTrack.load(.preferredTransform)
                let naturalSize = try await videoTrack.load(.naturalSize)

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: compositionVideoTrack)
                layerInstruction.setTransform(originalTransform, at: currentTime)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)

                // Update current time for next clip
                currentTime = CMTimeAdd(currentTime, clipDuration)
            } catch {
                print("Error processing clip: \(error)")
                continue
            }
        }

        // Setup video composition
        if let firstClip = clips.first,
           let videoTrack = try? await firstClip.asset.loadTracks(withMediaType: .video).first
        {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
            let renderWidth = isVideoPortrait ? naturalSize.height : naturalSize.width
            let renderHeight = isVideoPortrait ? naturalSize.width : naturalSize.height

            videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = instructions
        }

        // Create player item with composition
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        self.playerItem = playerItem

        // Create and configure player
        let player = AVPlayer(playerItem: playerItem)
        _player = player

        // Add time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            guard let self = self else { return }

            let currentTime = time.seconds
            if currentTime >= self.totalDuration {
                Task { @MainActor in
                    await player.seek(to: .zero)
                    player.play()
                }
            }
        }

        // Set initial volume
        updatePlayerVolume()
    }

    private func updatePlayerTime() {
        guard let player = _player else { return }
        Task { @MainActor in
            await player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            player.play()
        }
    }

    private func updatePlayerVolume() {
        guard let clip = selectedClip else { return }
        _player?.volume = Float(clip.volume)
    }

    private func updatePlayerItem() {
        // For now, we'll just update the player item's properties
        // In a more complete implementation, you would apply video filters here
        // using AVVideoComposition and CIFilters
    }

    var selectedClip: VideoClip? {
        guard let index = selectedClipIndex, clips.indices.contains(index) else { return nil }
        return clips[index]
    }

    func updateClipTrim(startTime: Double, endTime: Double) {
        guard var clip = selectedClip,
              let index = selectedClipIndex
        else { return }

        clip.startTime = startTime
        clip.endTime = endTime
        clips[index] = clip

        // Update player with new composition
        Task {
            try? await setupPlayerWithComposition()
            // Seek to start of modified clip
            if let player = _player {
                await player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
            }
        }
    }

    func updateClipVolume(_ volume: Double) {
        guard var clip = selectedClip,
              let index = selectedClipIndex
        else { return }

        clip.volume = volume
        clips[index] = clip
        updatePlayerVolume()
    }

    func moveClip(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
        if let selected = selectedClipIndex,
           let sourceFirst = source.first
        {
            selectedClipIndex = sourceFirst < selected ? (selected - 1) : (selected + 1)
        }
        // Update player with new clip order
        Task {
            try? await setupPlayerWithComposition()
        }
    }

    func deleteClip(at index: Int) {
        clips.remove(at: index)
        if selectedClipIndex == index {
            selectedClipIndex = clips.isEmpty ? nil : min(index, clips.count - 1)
        }
        // Update player with remaining clips
        Task {
            try? await setupPlayerWithComposition()
        }
    }

    func exportVideo() async throws -> URL {
        guard !clips.isEmpty else {
            throw NSError(
                domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No clips to export"]
            )
        }

        isProcessing = true
        defer { isProcessing = false }

        // Create composition
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()

        // Create composition tracks
        guard
            let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw NSError(
                domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create composition tracks"]
            )
        }

        var currentTime = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var audioMixParameters: [AVMutableAudioMixInputParameters] = []

        // Process each clip
        for clip in clips {
            do {
                // Load tracks for current clip
                let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first
                let audioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first

                guard let videoTrack = videoTrack, let audioTrack = audioTrack else { continue }

                // Calculate time range for the clip
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: clip.startTime, preferredTimescale: 600),
                    end: CMTime(seconds: clip.endTime, preferredTimescale: 600)
                )
                let clipDuration = timeRange.duration

                // Insert tracks into composition
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: currentTime)
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: currentTime)

                // Create instruction for this clip
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: currentTime, duration: clipDuration)

                // Get and apply the original transform
                let originalTransform = try await videoTrack.load(.preferredTransform)
                let naturalSize = try await videoTrack.load(.naturalSize)

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: compositionVideoTrack)
                layerInstruction.setTransform(originalTransform, at: currentTime)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)

                // Setup audio parameters
                let audioParams = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                audioParams.setVolume(Float(clip.volume), at: currentTime)
                audioMixParameters.append(audioParams)

                // Update current time for next clip
                currentTime = CMTimeAdd(currentTime, clipDuration)

            } catch {
                print("Error processing clip: \(error)")
                continue
            }
        }

        // Setup video composition
        if let firstClip = clips.first,
           let videoTrack = try? await firstClip.asset.loadTracks(withMediaType: .video).first
        {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
            let renderWidth = isVideoPortrait ? naturalSize.height : naturalSize.width
            let renderHeight = isVideoPortrait ? naturalSize.width : naturalSize.height

            videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = instructions
        }

        // Create temporary URL for export
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(UUID().uuidString).mp4")

        // Setup export session
        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            )
        else {
            throw NSError(
                domain: "", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        // Set audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParameters
        exportSession.audioMix = audioMix

        // Export the video
        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        return outputURL
    }

    func cleanup() {
        if let timeObserver = timeObserver {
            _player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        _player?.pause()
        _player = nil
        playerItem = nil
        clips.removeAll()
        selectedClipIndex = nil
    }

    func swapClips(at index: Int) {
        guard index < clips.count - 1 else { return }

        // Swap the clips
        clips.swapAt(index, index + 1)

        // Update selected clip index if needed
        if selectedClipIndex == index {
            selectedClipIndex = index + 1
        } else if selectedClipIndex == index + 1 {
            selectedClipIndex = index
        }

        // Update player with new clip order
        Task {
            try? await setupPlayerWithComposition()
        }
    }

    func splitClip(at time: Double) async {
        // Find which clip contains this time
        var accumulatedTime: Double = 0
        for (index, clip) in clips.enumerated() {
            let clipDuration = clip.endTime - clip.startTime
            let clipEndTime = accumulatedTime + clipDuration

            if time > accumulatedTime && time < clipEndTime {
                // Calculate the relative split point within this clip
                let relativeTime = time - accumulatedTime + clip.startTime

                // Create two new clips from the original
                var firstHalf = VideoClip(
                    asset: clip.asset,
                    startTime: clip.startTime,
                    endTime: relativeTime,
                    thumbnail: nil
                )

                var secondHalf = VideoClip(
                    asset: clip.asset,
                    startTime: relativeTime,
                    endTime: clip.endTime,
                    thumbnail: nil
                )

                // Generate new thumbnails for both clips
                do {
                    let imageGenerator = AVAssetImageGenerator(asset: clip.asset)
                    imageGenerator.appliesPreferredTrackTransform = true

                    // Generate thumbnail for first half at its midpoint
                    let firstHalfMidpoint = CMTime(
                        seconds: (firstHalf.startTime + firstHalf.endTime) / 2,
                        preferredTimescale: 600
                    )
                    let firstHalfImage = try imageGenerator.copyCGImage(
                        at: firstHalfMidpoint, actualTime: nil
                    )
                    firstHalf.thumbnail = UIImage(cgImage: firstHalfImage)

                    // Generate thumbnail for second half at its midpoint
                    let secondHalfMidpoint = CMTime(
                        seconds: (secondHalf.startTime + secondHalf.endTime) / 2,
                        preferredTimescale: 600
                    )
                    let secondHalfImage = try imageGenerator.copyCGImage(
                        at: secondHalfMidpoint, actualTime: nil
                    )
                    secondHalf.thumbnail = UIImage(cgImage: secondHalfImage)
                } catch {
                    print("Error generating thumbnails for split clips: \(error)")
                    // If we fail to generate new thumbnails, use the original for both
                    firstHalf.thumbnail = clip.thumbnail
                    secondHalf.thumbnail = clip.thumbnail
                }

                // Replace the original clip with the two new ones
                clips.remove(at: index)
                clips.insert(secondHalf, at: index)
                clips.insert(firstHalf, at: index)

                // Update selected clip index if needed
                if selectedClipIndex == index {
                    selectedClipIndex = index // Select first half
                } else if selectedClipIndex != nil && selectedClipIndex! > index {
                    selectedClipIndex! += 1 // Shift selection for clips after the split
                }

                // Update player with new clips
                try? await setupPlayerWithComposition()
                return
            }

            accumulatedTime += clipDuration
        }
    }
}

// Custom video compositor for applying filters
class VideoCompositor: NSObject, AVVideoCompositing {
    let renderContext = CIContext()
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

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
