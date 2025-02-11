@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import SwiftUI
import UIKit

enum VideoError: Error {
    case noVideoTrack
    case noComposition
    case exportSessionCreationFailed
    case exportFailed
}

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

    // Thread-safe player access
    private var _player: AVPlayer?
    var player: AVPlayer? {
        get { _player }
        set { _player = newValue }
    }

    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var videoTrack: AVAssetTrack?

    // Make totalDuration thread-safe
    private var _totalDuration: Double = 0
    var totalDuration: Double {
        get { _totalDuration }
        set { _totalDuration = newValue }
    }

    private var composition: AVMutableComposition?

    private let poseDetectionService = PoseDetectionService()
    private let setDetectionService = SetDetectionService()
    @Published private(set) var poseDetectionInProgress = false
    @Published private(set) var detectedSets: [DetectedExerciseSet] = []

    private func setupVideoComposition(for composition: AVMutableComposition, clips: [VideoClip]) async throws -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Set color properties to maintain correct color appearance
        videoComposition.colorPrimaries = kCVImageBufferColorPrimaries_ITU_R_709_2 as String
        videoComposition.colorYCbCrMatrix = kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String
        videoComposition.colorTransferFunction = kCVImageBufferTransferFunction_ITU_R_709_2 as String

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var currentTime = CMTime.zero

        // Get all composition video tracks
        let compositionTracks = composition.tracks(withMediaType: .video)

        // Process each clip
        for (index, clip) in clips.enumerated() {
            if let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first,
               let compositionTrack = compositionTracks[safe: index]
            {
                // Create instruction for this clip
                let instruction = AVMutableVideoCompositionInstruction()
                let clipDuration = CMTime(seconds: clip.assetDuration, preferredTimescale: 600)
                instruction.timeRange = CMTimeRange(start: currentTime, duration: clipDuration)

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)

                // Get the original transform and properties
                let transform = try await videoTrack.load(.preferredTransform)
                let naturalSize = try await videoTrack.load(.naturalSize)

                // Set initial transform with color properties
                layerInstruction.setTransform(transform, at: currentTime)
                layerInstruction.setOpacity(1.0, at: currentTime)

                // Handle zoom effect if configured
                if let zoomConfig = clip.zoomConfig {
                    // Calculate zoom transform while preserving color properties
                    var zoomTransform = transform
                    let scale: CGFloat = 1.5
                    let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

                    // Center the scaling
                    let tx = (naturalSize.width * (scale - 1)) / 2
                    let ty = (naturalSize.height * (scale - 1)) / 2
                    let centeringTransform = CGAffineTransform(translationX: -tx, y: -ty)

                    // Combine transforms while preserving color properties
                    zoomTransform = transform
                        .concatenating(centeringTransform)
                        .concatenating(scaleTransform)

                    // Handle zoom in
                    let zoomInStart = CMTime(seconds: clip.startTime + zoomConfig.startZoomIn, preferredTimescale: 600)

                    // Set color properties for initial state
                    layerInstruction.setOpacity(1.0, at: currentTime)

                    if let zoomInComplete = zoomConfig.zoomInComplete {
                        let zoomInEnd = CMTime(seconds: clip.startTime + zoomInComplete, preferredTimescale: 600)
                        // Apply transform ramp with preserved color properties
                        layerInstruction.setTransformRamp(
                            fromStart: transform,
                            toEnd: zoomTransform,
                            timeRange: CMTimeRange(start: zoomInStart, end: zoomInEnd)
                        )
                        // Ensure color properties are maintained during zoom
                        layerInstruction.setOpacity(1.0, at: zoomInStart)
                        layerInstruction.setOpacity(1.0, at: zoomInEnd)
                    } else {
                        layerInstruction.setTransform(zoomTransform, at: zoomInStart)
                        layerInstruction.setOpacity(1.0, at: zoomInStart)
                    }

                    // Handle zoom out if specified
                    if let startZoomOut = zoomConfig.startZoomOut {
                        let zoomOutStart = CMTime(seconds: clip.startTime + startZoomOut, preferredTimescale: 600)

                        if let zoomOutComplete = zoomConfig.zoomOutComplete {
                            let zoomOutEnd = CMTime(seconds: clip.startTime + zoomOutComplete, preferredTimescale: 600)
                            // Apply transform ramp with preserved color properties
                            layerInstruction.setTransformRamp(
                                fromStart: zoomTransform,
                                toEnd: transform,
                                timeRange: CMTimeRange(start: zoomOutStart, end: zoomOutEnd)
                            )
                            // Ensure color properties are maintained during zoom out
                            layerInstruction.setOpacity(1.0, at: zoomOutStart)
                            layerInstruction.setOpacity(1.0, at: zoomOutEnd)
                        } else {
                            layerInstruction.setTransform(transform, at: zoomOutStart)
                            layerInstruction.setOpacity(1.0, at: zoomOutStart)
                        }
                    }
                } else {
                    // Set initial transform with color properties
                    layerInstruction.setTransform(transform, at: currentTime)
                    layerInstruction.setOpacity(1.0, at: currentTime)
                }

                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)

                // Set video composition render size if not already set
                if videoComposition.renderSize == .zero {
                    let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
                    videoComposition.renderSize = CGSize(
                        width: isVideoPortrait ? naturalSize.height : naturalSize.width,
                        height: isVideoPortrait ? naturalSize.width : naturalSize.height
                    )
                }

                currentTime = currentTime + clipDuration
            }
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    @MainActor
    func addClip(from url: URL) async throws {
        isProcessing = true

        do {
            let asset = AVURLAsset(url: url)

            // Generate thumbnail for new clip asynchronously
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero

            // Start thumbnail generation early
            let thumbnailTask = Task {
                let time = CMTime(seconds: 0.03, preferredTimescale: 600)
                let image = try await imageGenerator.image(at: time)
                return UIImage(cgImage: image.image)
            }

            // Create composition if it doesn't exist
            let newComposition = composition ?? AVMutableComposition()
            var currentTime = CMTime(seconds: totalDuration, preferredTimescale: 600)

            // Process the new clip
            let videoTracks = try await asset.loadTracks(withMediaType: AVMediaType.video)
            guard let videoTrack = videoTracks.first else {
                throw VideoError.noVideoTrack
            }

            let assetDuration = try await asset.load(.duration)

            // Add video track
            let compositionVideoTrack = newComposition.addMutableTrack(
                withMediaType: AVMediaType.video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )

            try compositionVideoTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: videoTrack,
                at: currentTime
            )

            // Add audio track if available
            if let audioTrack = try await asset.loadTracks(withMediaType: AVMediaType.audio).first {
                let compositionAudioTrack = newComposition.addMutableTrack(
                    withMediaType: AVMediaType.audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )

                try compositionAudioTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: assetDuration),
                    of: audioTrack,
                    at: currentTime
                )
            }

            // Wait for thumbnail generation to complete
            let thumbnail = try await thumbnailTask.value

            // Create clip model for the new clip
            let newClip = VideoClip(
                asset: asset,
                startTime: currentTime.seconds,
                endTime: (currentTime + assetDuration).seconds,
                thumbnail: thumbnail,
                assetStartTime: 0,
                assetDuration: assetDuration.seconds
            )

            // Add clip and start pose detection
            clips.append(newClip)
            startPoseDetection(for: newClip)

            // Update state
            composition = newComposition
            totalDuration = (currentTime + assetDuration).seconds

            // Update player
            await updatePlayer()

        } catch {
            print("Error adding clip: \(error)")
            throw error
        }

        isProcessing = false
    }

    private func updatePlayer() {
        guard let composition = composition else { return }

        Task { @MainActor in
            // Create player item with composition
            let playerItem = AVPlayerItem(asset: composition)

            // Create or update player
            if let player = player {
                player.pause()
                player.replaceCurrentItem(with: playerItem)
            } else {
                player = AVPlayer(playerItem: playerItem)
            }

            // Setup time observer only once when creating new player
            if timeObserver == nil {
                setupTimeObserver()
            }

            // Enable player controls and start playback
            player?.allowsExternalPlayback = true
            player?.appliesMediaSelectionCriteriaAutomatically = true
            player?.preventsDisplaySleepDuringVideoPlayback = true
            player?.play()
        }
    }

    private func setupTimeObserver() {
        guard let player = player, timeObserver == nil else { return }

        // Add new time observer with optimized interval
        let interval = CMTime(value: 1, timescale: 30) // Update 30 times per second
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentPosition = time.seconds
            }
        }
    }

    private func updatePlayerTime() {
        guard let player = _player else { return }
        Task { @MainActor in
            // Use more precise seeking
            await player.seek(
                to: CMTime(seconds: startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
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
            await setupPlayerWithComposition()
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
            await setupPlayerWithComposition()
        }
    }

    func deleteClip(at index: Int) {
        // Remove the clip from the array
        clips.remove(at: index)

        // Update selected clip index
        if selectedClipIndex == index {
            selectedClipIndex = clips.isEmpty ? nil : min(index, clips.count - 1)
        } else if let selected = selectedClipIndex, selected > index {
            selectedClipIndex = selected - 1
        }

        // Create new composition with remaining clips
        Task {
            // Remove existing time observer before rebuilding
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
                timeObserver = nil
            }

            await MainActor.run {
                isProcessing = true
            }

            do {
                try await rebuildComposition()
                await MainActor.run {
                    isProcessing = false
                }
            } catch {
                print("Error in deleteClip: \(error)")
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }

    func exportVideo() async throws -> URL {
        guard let composition = composition else { throw VideoError.noComposition }

        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        // Create export session on the main actor to avoid data races
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportSessionCreationFailed
        }

        // Create video composition for export
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var currentTime = CMTime.zero

        // Process each clip to create video composition instructions
        for clip in clips {
            if let videoTrack = try await clip.asset.loadTracks(withMediaType: AVMediaType.video).first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)

                // Set video composition render size if not already set
                if videoComposition.renderSize == .zero {
                    let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
                    videoComposition.renderSize = CGSize(
                        width: isVideoPortrait ? naturalSize.height : naturalSize.width,
                        height: isVideoPortrait ? naturalSize.width : naturalSize.height
                    )
                }

                // Create instruction for this clip
                let instruction = AVMutableVideoCompositionInstruction()
                let duration = CMTime(seconds: clip.assetDuration, preferredTimescale: 600)
                instruction.timeRange = CMTimeRange(start: currentTime, duration: duration)

                if let compositionTrack = composition.tracks(withMediaType: AVMediaType.video).first {
                    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
                    layerInstruction.setTransform(transform, at: currentTime)
                    instruction.layerInstructions = [layerInstruction]
                }

                instructions.append(instruction)
                currentTime = currentTime + duration
            }
        }

        videoComposition.instructions = instructions

        // Configure export session
        exportSession.videoComposition = videoComposition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Export using the modern async/await API
        try await exportSession.export(to: outputURL, as: .mp4)

        // Monitor export states using async sequence
        for try await state in exportSession.states() {
            switch state {
            case .pending:
                continue
            case .waiting:
                continue
            case let .exporting(progress):
                print("Export progress: \(progress.fractionCompleted)")
                continue
            @unknown default:
                continue
            }
        }

        // After the export completes, check if the file exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        } else {
            throw VideoError.exportFailed
        }
    }

    private func rebuildComposition() async throws {
        print("Starting composition rebuild")
        let newComposition = AVMutableComposition()
        var currentTime = CMTime.zero

        // Process each clip
        for (index, clip) in clips.enumerated() {
            print("Processing clip \(index) with startTime: \(clip.startTime), endTime: \(clip.endTime)")

            if let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first {
                // Add video track
                let compositionVideoTrack = newComposition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )

                let timeRange = CMTimeRange(
                    start: CMTime(seconds: clip.assetStartTime, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.assetDuration, preferredTimescale: 600)
                )

                try compositionVideoTrack?.insertTimeRange(
                    timeRange,
                    of: videoTrack,
                    at: currentTime
                )

                // Add audio if available
                if let audioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
                    let compositionAudioTrack = newComposition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )

                    try compositionAudioTrack?.insertTimeRange(
                        timeRange,
                        of: audioTrack,
                        at: currentTime
                    )
                }

                currentTime = currentTime + CMTime(seconds: clip.assetDuration, preferredTimescale: 600)
            }
        }

        // Setup video composition using the helper
        let videoComposition = try await setupVideoComposition(for: newComposition, clips: clips)

        await MainActor.run {
            // Update the composition
            self.composition = newComposition
            let newDuration = currentTime.seconds
            totalDuration = newDuration

            // Ensure current position is within valid range
            currentPosition = min(currentPosition, newDuration)
            if currentPosition >= newDuration {
                currentPosition = max(0, newDuration - 0.1)
            }

            // Create new player item with the updated composition
            let playerItem = AVPlayerItem(asset: newComposition)
            playerItem.videoComposition = videoComposition

            if let player = player {
                player.replaceCurrentItem(with: playerItem)
            } else {
                player = AVPlayer(playerItem: playerItem)
            }

            // Setup time observer if needed
            if timeObserver == nil {
                setupTimeObserver()
            }

            // Seek to current position and play
            Task {
                await player?.seek(
                    to: CMTime(seconds: currentPosition, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                player?.play()
            }
        }
    }

    func cleanup() {
        if let observer = timeObserver {
            _player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        _player?.pause()
        _player = nil
        playerItem = nil
        clips.removeAll()
        selectedClipIndex = nil
        composition = nil
        totalDuration = 0
    }

    private func setupPlayerWithComposition() async {
        print("Starting setupPlayerWithComposition")
        guard let _ = composition else {
            print("No composition available")
            return
        }

        do {
            try await rebuildComposition()
            print("Successfully completed setupPlayerWithComposition")
        } catch {
            print("Error in setupPlayerWithComposition: \(error.localizedDescription)")
            print("Error details: \(error)")
        }
    }

    func swapClips(at index: Int) {
        print("Starting swapClips at index: \(index)")
        guard index < clips.count - 1 else {
            print("Invalid swap index")
            return
        }

        // First update the clips array
        clips.swapAt(index, index + 1)
        print("Swapped clips at indices \(index) and \(index + 1)")

        // Update selected clip index if needed
        if selectedClipIndex == index {
            selectedClipIndex = index + 1
            print("Updated selected clip index to: \(index + 1)")
        } else if selectedClipIndex == index + 1 {
            selectedClipIndex = index
            print("Updated selected clip index to: \(index)")
        }

        // Rebuild the composition with the new clip order
        Task {
            print("Starting composition rebuild")
            await MainActor.run {
                isProcessing = true
            }

            // Recalculate clip times based on their new positions
            var currentTime = 0.0
            for i in 0 ..< clips.count {
                let clipDuration = clips[i].endTime - clips[i].startTime
                var updatedClip = clips[i]
                updatedClip.startTime = currentTime
                updatedClip.endTime = currentTime + clipDuration
                clips[i] = updatedClip
                print("Updated clip \(i) times - start: \(currentTime), end: \(currentTime + clipDuration)")
                currentTime += clipDuration
            }

            do {
                try await rebuildComposition()
                await MainActor.run {
                    isProcessing = false
                    print("Completed swapClips operation")
                }
            } catch {
                print("Error in swapClips: \(error.localizedDescription)")
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }

    func splitClip(at time: Double) async {
        print("Starting splitClip operation at time: \(time)")
        if clips.isEmpty ||
            !time.isFinite ||
            time.isNaN
        {
            print("Invalid split parameters")
            return
        }

        // Find which clip contains the split point
        var accumulatedTime = 0.0
        var clipToSplit: Int?

        for (index, clip) in clips.enumerated() {
            let clipEnd = accumulatedTime + (clip.endTime - clip.startTime)
            if time > accumulatedTime && time < clipEnd {
                clipToSplit = index
                break
            }
            accumulatedTime = clipEnd
        }

        guard let clipIndex = clipToSplit else {
            print("Split time outside any clip bounds")
            return
        }

        let relativeTime = time - accumulatedTime
        print("Splitting clip \(clipIndex) at relative time \(relativeTime)")

        await MainActor.run {
            isProcessing = true
            print("Set isProcessing to true")
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                print("Set isProcessing to false")
            }
        }

        do {
            // Create a new composition
            let newComposition = AVMutableComposition()
            var currentTime = CMTime.zero

            // Process each clip
            for (index, currentClip) in clips.enumerated() {
                if index == clipIndex {
                    // Get the video track from the original asset
                    guard let videoTrack = try await currentClip.asset.loadTracks(withMediaType: AVMediaType.video).first else {
                        print("No video track found")
                        continue
                    }

                    // First part
                    let firstVideoTrack = newComposition.addMutableTrack(
                        withMediaType: AVMediaType.video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )

                    let firstPartRange = CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: relativeTime, preferredTimescale: 600)
                    )

                    try firstVideoTrack?.insertTimeRange(
                        firstPartRange,
                        of: videoTrack,
                        at: currentTime
                    )

                    // Add audio for first part
                    if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: AVMediaType.audio).first {
                        let firstAudioTrack = newComposition.addMutableTrack(
                            withMediaType: AVMediaType.audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        try firstAudioTrack?.insertTimeRange(
                            firstPartRange,
                            of: audioTrack,
                            at: currentTime
                        )
                    }

                    currentTime = currentTime + firstPartRange.duration

                    // Second part
                    let secondVideoTrack = newComposition.addMutableTrack(
                        withMediaType: AVMediaType.video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )

                    let secondPartRange = CMTimeRange(
                        start: CMTime(seconds: relativeTime, preferredTimescale: 600),
                        duration: CMTime(seconds: currentClip.endTime - currentClip.startTime - relativeTime, preferredTimescale: 600)
                    )

                    try secondVideoTrack?.insertTimeRange(
                        secondPartRange,
                        of: videoTrack,
                        at: currentTime
                    )

                    // Add audio for second part
                    if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: AVMediaType.audio).first {
                        let secondAudioTrack = newComposition.addMutableTrack(
                            withMediaType: AVMediaType.audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        try secondAudioTrack?.insertTimeRange(
                            secondPartRange,
                            of: audioTrack,
                            at: currentTime
                        )
                    }

                    currentTime = currentTime + secondPartRange.duration

                    // Generate thumbnails for both parts
                    let imageGenerator = AVAssetImageGenerator(asset: currentClip.asset)
                    imageGenerator.appliesPreferredTrackTransform = true
                    imageGenerator.maximumSize = CGSize(width: 200, height: 200)
                    imageGenerator.requestedTimeToleranceBefore = .zero
                    imageGenerator.requestedTimeToleranceAfter = .zero

                    // Thumbnail for first part
                    let firstThumbnailTime = CMTime(seconds: 0.03, preferredTimescale: 600)
                    let firstImage = try await imageGenerator.image(at: firstThumbnailTime)
                    let firstThumbnail = UIImage(cgImage: firstImage.image)

                    // Thumbnail for second part
                    let secondThumbnailTime = CMTime(seconds: relativeTime + 0.03, preferredTimescale: 600)
                    let secondImage = try await imageGenerator.image(at: secondThumbnailTime)
                    let secondThumbnail = UIImage(cgImage: secondImage.image)

                    // Update clips array
                    await MainActor.run {
                        // Update the original clip with first part
                        var firstClip = clips[clipIndex]
                        firstClip.thumbnail = firstThumbnail
                        firstClip.endTime = time
                        firstClip.assetDuration = relativeTime
                        clips[clipIndex] = firstClip

                        // Create and insert the second part
                        let secondClip = VideoClip(
                            asset: currentClip.asset,
                            startTime: time,
                            endTime: currentClip.endTime,
                            thumbnail: secondThumbnail,
                            assetStartTime: relativeTime,
                            assetDuration: currentClip.assetDuration - relativeTime
                        )
                        clips.insert(secondClip, at: clipIndex + 1)
                    }
                } else {
                    // Copy this clip as is
                    guard let videoTrack = try await currentClip.asset.loadTracks(withMediaType: AVMediaType.video).first else { continue }

                    let clipDuration = currentClip.endTime - currentClip.startTime
                    let clipTimeRange = CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
                    )

                    let compositionVideoTrack = newComposition.addMutableTrack(
                        withMediaType: AVMediaType.video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )

                    try compositionVideoTrack?.insertTimeRange(
                        clipTimeRange,
                        of: videoTrack,
                        at: currentTime
                    )

                    // Add audio if available
                    if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: AVMediaType.audio).first {
                        let compositionAudioTrack = newComposition.addMutableTrack(
                            withMediaType: AVMediaType.audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        try compositionAudioTrack?.insertTimeRange(
                            clipTimeRange,
                            of: audioTrack,
                            at: currentTime
                        )
                    }

                    currentTime = currentTime + clipTimeRange.duration
                }
            }

            // Setup video composition using the helper
            let videoComposition = try await setupVideoComposition(for: newComposition, clips: clips)

            // Update the composition and player
            await MainActor.run {
                self.composition = newComposition
                totalDuration = currentTime.seconds

                // Create new player item with the updated composition
                let playerItem = AVPlayerItem(asset: newComposition)
                playerItem.videoComposition = videoComposition

                if let player = player {
                    player.replaceCurrentItem(with: playerItem)
                } else {
                    player = AVPlayer(playerItem: playerItem)
                }

                // Setup time observer if needed
                if timeObserver == nil {
                    setupTimeObserver()
                }

                // Seek to the split point and play
                Task {
                    await player?.seek(
                        to: CMTime(seconds: time, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                    player?.play()
                }
            }

            print("Successfully completed splitClip operation")
        } catch {
            print("Error in splitClip: \(error.localizedDescription)")
            print("Error details: \(error)")
        }
    }

    // Fix unused naturalSize warning
    private func configureVideoComposition(_ videoComposition: AVMutableVideoComposition, with videoTrack: AVAssetTrack) async throws {
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)

        let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
        let renderWidth = isVideoPortrait ? size.height : size.width
        let renderHeight = isVideoPortrait ? size.width : size.height

        videoComposition.renderSize = CGSize(width: renderWidth, height: renderHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    }

    @MainActor
    func updateZoomConfig(at index: Int, config: ZoomConfig?) {
        guard index < clips.count else { return }
        var updatedClip = clips[index]
        updatedClip.zoomConfig = config
        clips[index] = updatedClip

        // Rebuild the composition to apply the zoom effect
        Task {
            await setupPlayerWithComposition()
        }
    }

    private func startPoseDetection(for clip: VideoClip) {
        Task {
            do {
                print("🏃‍♂️ Starting pose detection for clip: \(clip.id)")
                var updatedClip = clip
                updatedClip.poseDetectionStatus = .inProgress
                updateClip(updatedClip)

                let results = try await poseDetectionService.detectPoses(for: clip)
                print("✅ Pose detection completed. Found \(results.count) pose frames")

                // Detect sets from pose results
                let sets = setDetectionService.detectSets(from: results)
                print("💪 Set detection completed. Found \(sets.count) sets:")
                for (index, set) in sets.enumerated() {
                    print("  Set \(index + 1): \(set.reps) reps, from \(String(format: "%.2f", set.startTime))s to \(String(format: "%.2f", set.endTime))s")
                }

                await MainActor.run {
                    detectedSets = sets
                }

                updatedClip.poseResults = results
                updatedClip.poseDetectionStatus = .completed
                updateClip(updatedClip)
                print("🎬 Finished processing clip: \(clip.id)")
            } catch {
                print("❌ Error during pose/set detection: \(error)")
                var updatedClip = clip
                updatedClip.poseDetectionStatus = .failed(error)
                updateClip(updatedClip)
            }
        }
    }

    private func updateClip(_ updatedClip: VideoClip) {
        if let index = clips.firstIndex(where: { $0.id == updatedClip.id }) {
            clips[index] = updatedClip
        }
    }

    func export() async throws -> URL {
        // Wait for all pose detection to complete
        for clip in clips {
            while clip.poseDetectionStatus == .pending || clip.poseDetectionStatus == .inProgress {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if case let .failed(error) = clip.poseDetectionStatus {
                throw error
            }
        }

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        // Ensure composition and video composition are ready
        guard let composition = composition else {
            throw VideoError.noComposition
        }

        let videoComposition = try await setupVideoComposition(for: composition, clips: clips)

        // Configure export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition

        // Export the video
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? VideoError.exportFailed
        }

        return outputURL
    }

    deinit {
        // Cancel any ongoing pose detection tasks
        Task { @MainActor in
            for clip in clips {
                await poseDetectionService.cancelDetection(for: clip.id)
            }
        }
    }
}

// Helper extension to safely access array elements
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
