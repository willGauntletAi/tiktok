@preconcurrency import AVFoundation
@preconcurrency import CoreImage
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

    func addClip(from url: URL) async throws {
        print("Starting addClip operation from URL: \(url)")
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
            let asset = AVURLAsset(url: url)
            print("Created AVURLAsset")

            // Create composition if needed
            if composition == nil {
                composition = AVMutableComposition()
                print("Created new composition")
            }

            guard let composition = composition else {
                print("Failed to get composition")
                throw VideoError.compositionCreationFailed
            }

            // Generate thumbnail
            print("Starting thumbnail generation")
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero

            let time = CMTime(seconds: 0.03, preferredTimescale: 600)
            let image = try await imageGenerator.image(at: time)
            let thumbnail = UIImage(cgImage: image.image)
            print("Successfully generated thumbnail")

            // Insert video track
            print("Loading video tracks")
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                print("No video track found")
                throw VideoError.noVideoTrack
            }

            // Load video properties
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)

            print("Creating composition video track")
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                print("Failed to create composition video track")
                throw VideoError.trackCreationFailed
            }

            let timeRange = try await videoTrack.load(.timeRange)
            let insertTime = composition.duration
            print("Inserting video track at time: \(insertTime.seconds)")
            try compositionVideoTrack.insertTimeRange(
                timeRange,
                of: videoTrack,
                at: insertTime
            )

            // Create or update video composition
            let videoComposition: AVMutableVideoComposition
            if let existingVideoComposition = (player?.currentItem?.videoComposition as? AVMutableVideoComposition)?.copy() as? AVMutableVideoComposition {
                videoComposition = existingVideoComposition
            } else {
                videoComposition = AVMutableVideoComposition()
                videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

                // Set initial render size based on first video
                let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
                videoComposition.renderSize = CGSize(
                    width: isVideoPortrait ? naturalSize.height : naturalSize.width,
                    height: isVideoPortrait ? naturalSize.width : naturalSize.height
                )
            }

            // Create instruction for the new clip
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: insertTime, duration: timeRange.duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            // Update instructions
            var instructions = videoComposition.instructions as? [AVMutableVideoCompositionInstruction] ?? []
            instructions.append(instruction)
            videoComposition.instructions = instructions

            // Insert audio track if available
            print("Loading audio tracks")
            let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks?.first {
                print("Found audio track, creating composition audio track")
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    print("Failed to create composition audio track")
                    throw VideoError.trackCreationFailed
                }

                print("Inserting audio track")
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertTime
                )
            }

            // Create clip model with correct time range
            let clip = VideoClip(
                asset: asset,
                startTime: insertTime.seconds,
                endTime: (insertTime + timeRange.duration).seconds,
                thumbnail: thumbnail
            )
            print("Created clip model with duration: \(timeRange.duration.seconds)")

            // Update UI
            await MainActor.run {
                print("Updating UI")
                clips.append(clip)
                selectedClipIndex = clips.count - 1
                totalDuration = composition.duration.seconds
                print("Total duration updated to: \(totalDuration)")

                // Create new player item with the updated composition
                let playerItem = AVPlayerItem(asset: composition)
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

                player?.play()
            }

            print("Successfully completed addClip operation")
        } catch {
            print("Error in addClip: \(error.localizedDescription)")
            print("Error details: \(error)")
            throw error
        }
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

            // Set initial playback rate and volume
            player?.rate = 1.0
            player?.volume = 1.0
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
                // Create fresh composition
                composition = AVMutableComposition()
                var currentTime = CMTime.zero

                // Re-add all remaining clips
                for clip in clips {
                    // Add video track
                    let videoTracks = try await clip.asset.loadTracks(withMediaType: .video)
                    guard let videoTrack = videoTracks.first,
                          let compositionVideoTrack = composition?.addMutableTrack(
                              withMediaType: .video,
                              preferredTrackID: kCMPersistentTrackID_Invalid
                          ) else { continue }

                    let timeRange = CMTimeRange(
                        start: CMTime(seconds: clip.startTime, preferredTimescale: 600),
                        duration: CMTime(seconds: clip.endTime - clip.startTime, preferredTimescale: 600)
                    )

                    try compositionVideoTrack.insertTimeRange(
                        timeRange,
                        of: videoTrack,
                        at: currentTime
                    )

                    // Add audio track if available
                    if let audioTracks = try? await clip.asset.loadTracks(withMediaType: .audio),
                       let audioTrack = audioTracks.first,
                       let compositionAudioTrack = composition?.addMutableTrack(
                           withMediaType: .audio,
                           preferredTrackID: kCMPersistentTrackID_Invalid
                       )
                    {
                        try compositionAudioTrack.insertTimeRange(
                            timeRange,
                            of: audioTrack,
                            at: currentTime
                        )
                    }

                    currentTime = currentTime + CMTime(seconds: clip.endTime - clip.startTime, preferredTimescale: 600)
                }

                let newDuration = currentTime.seconds

                // Update total duration and player
                await MainActor.run {
                    // Update duration first
                    totalDuration = newDuration

                    // Ensure current position is within valid range
                    currentPosition = min(currentPosition, newDuration)
                    if currentPosition >= newDuration {
                        currentPosition = max(0, newDuration - 0.1)
                    }

                    // Create new player with the updated composition
                    let playerItem = AVPlayerItem(asset: composition!)
                    if let player = player {
                        player.replaceCurrentItem(with: playerItem)
                    } else {
                        player = AVPlayer(playerItem: playerItem)
                    }

                    // Setup new time observer
                    setupTimeObserver()

                    // Seek to current position
                    Task {
                        await player?.seek(
                            to: CMTime(seconds: currentPosition, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        player?.play()
                    }

                    isProcessing = false
                }
            } catch {
                print("Error rebuilding composition after delete: \(error)")
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
            await setupPlayerWithComposition()
        }
    }

    func splitClip(at time: Double) async {
        print("Starting splitClip operation at time: \(time)")
        guard !clips.isEmpty,
              time.isFinite,
              !time.isNaN,
              time > 0,
              let selectedIndex = selectedClipIndex,
              selectedIndex < clips.count
        else {
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

        let clip = clips[clipIndex]
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
            // Generate thumbnails for both parts
            let imageGenerator = AVAssetImageGenerator(asset: clip.asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)
            imageGenerator.requestedTimeToleranceBefore = .zero
            imageGenerator.requestedTimeToleranceAfter = .zero

            // Calculate asset-relative time for thumbnails
            let assetStartTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            let assetSplitTime = CMTime(seconds: clip.startTime + relativeTime, preferredTimescale: 600)

            // Thumbnail for first part (at start of this segment)
            let firstThumbnailTime = assetStartTime + CMTime(seconds: 0.03, preferredTimescale: 600)
            let firstImage = try await imageGenerator.image(at: firstThumbnailTime)
            let firstThumbnail = UIImage(cgImage: firstImage.image)

            // Thumbnail for second part (at split point plus a small offset)
            let secondThumbnailTime = assetSplitTime + CMTime(seconds: 0.03, preferredTimescale: 600)
            let secondImage = try await imageGenerator.image(at: secondThumbnailTime)
            let secondThumbnail = UIImage(cgImage: secondImage.image)

            // Create a new composition
            let newComposition = AVMutableComposition()
            var currentTime = CMTime.zero

            // Create video composition
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            var instructions: [AVMutableVideoCompositionInstruction] = []

            // Process each clip
            for (index, currentClip) in clips.enumerated() {
                if index == clipIndex {
                    // Add video track for first part
                    if let videoTrack = try await currentClip.asset.loadTracks(withMediaType: .video).first {
                        let naturalSize = try await videoTrack.load(.naturalSize)
                        let transform = try await videoTrack.load(.preferredTransform)

                        // First part: from clip start to split point
                        let firstVideoTrack = newComposition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        let firstPartRange = CMTimeRange(
                            start: CMTime(seconds: currentClip.startTime, preferredTimescale: 600),
                            end: CMTime(seconds: currentClip.startTime + relativeTime, preferredTimescale: 600)
                        )

                        try firstVideoTrack?.insertTimeRange(
                            firstPartRange,
                            of: videoTrack,
                            at: currentTime
                        )

                        // Create instruction for first part
                        let firstInstruction = AVMutableVideoCompositionInstruction()
                        firstInstruction.timeRange = CMTimeRange(start: currentTime, duration: firstPartRange.duration)

                        let firstLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: firstVideoTrack!)
                        firstLayerInstruction.setTransform(transform, at: .zero)
                        firstInstruction.layerInstructions = [firstLayerInstruction]
                        instructions.append(firstInstruction)

                        // Add audio track for first part if available
                        if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: .audio).first {
                            let firstAudioTrack = newComposition.addMutableTrack(
                                withMediaType: .audio,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            )

                            try firstAudioTrack?.insertTimeRange(
                                firstPartRange,
                                of: audioTrack,
                                at: currentTime
                            )
                        }

                        // Update current time after first part
                        currentTime = currentTime + firstPartRange.duration

                        // Second part: from split point to clip end
                        let secondVideoTrack = newComposition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        let secondPartRange = CMTimeRange(
                            start: CMTime(seconds: currentClip.startTime + relativeTime, preferredTimescale: 600),
                            end: CMTime(seconds: currentClip.endTime, preferredTimescale: 600)
                        )

                        try secondVideoTrack?.insertTimeRange(
                            secondPartRange,
                            of: videoTrack,
                            at: currentTime
                        )

                        // Create instruction for second part
                        let secondInstruction = AVMutableVideoCompositionInstruction()
                        secondInstruction.timeRange = CMTimeRange(start: currentTime, duration: secondPartRange.duration)

                        let secondLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: secondVideoTrack!)
                        secondLayerInstruction.setTransform(transform, at: .zero)
                        secondInstruction.layerInstructions = [secondLayerInstruction]
                        instructions.append(secondInstruction)

                        // Add audio track for second part if available
                        if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: .audio).first {
                            let secondAudioTrack = newComposition.addMutableTrack(
                                withMediaType: .audio,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            )

                            try secondAudioTrack?.insertTimeRange(
                                secondPartRange,
                                of: audioTrack,
                                at: currentTime
                            )
                        }

                        // Set video composition render size based on transform
                        let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
                        videoComposition.renderSize = CGSize(
                            width: isVideoPortrait ? naturalSize.height : naturalSize.width,
                            height: isVideoPortrait ? naturalSize.width : naturalSize.height
                        )

                        // Update current time for the second part
                        currentTime = currentTime + secondPartRange.duration

                        // Update clips array
                        await MainActor.run {
                            // Update the original clip with first part
                            var firstClip = clips[clipIndex]
                            firstClip.thumbnail = firstThumbnail
                            firstClip.endTime = firstClip.startTime + relativeTime
                            clips[clipIndex] = firstClip

                            // Create and insert the second part
                            let secondClip = VideoClip(
                                asset: currentClip.asset,
                                startTime: firstClip.endTime,
                                endTime: currentClip.endTime,
                                thumbnail: secondThumbnail
                            )
                            clips.insert(secondClip, at: clipIndex + 1)
                        }
                    }
                } else {
                    // For non-split clips, just add them as is
                    if let videoTrack = try await currentClip.asset.loadTracks(withMediaType: .video).first {
                        let naturalSize = try await videoTrack.load(.naturalSize)
                        let transform = try await videoTrack.load(.preferredTransform)

                        let compositionVideoTrack = newComposition.addMutableTrack(
                            withMediaType: .video,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )

                        let clipTimeRange = CMTimeRange(
                            start: CMTime(seconds: currentClip.startTime, preferredTimescale: 600),
                            end: CMTime(seconds: currentClip.endTime, preferredTimescale: 600)
                        )

                        try compositionVideoTrack?.insertTimeRange(
                            clipTimeRange,
                            of: videoTrack,
                            at: currentTime
                        )

                        // Create instruction for this clip
                        let instruction = AVMutableVideoCompositionInstruction()
                        instruction.timeRange = CMTimeRange(start: currentTime, duration: clipTimeRange.duration)

                        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
                        layerInstruction.setTransform(transform, at: .zero)
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

                        // Add audio if available
                        if let audioTrack = try await currentClip.asset.loadTracks(withMediaType: .audio).first {
                            let compositionAudioTrack = newComposition.addMutableTrack(
                                withMediaType: .audio,
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
            }

            // Set instructions on video composition
            videoComposition.instructions = instructions

            // Update the composition and player
            await MainActor.run {
                composition = newComposition
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

    private func setupPlayerWithComposition() async {
        guard let composition = composition else { return }

        await MainActor.run {
            // Create player item
            let playerItem = AVPlayerItem(asset: composition)

            // Create or update player
            if let player = player {
                player.replaceCurrentItem(with: playerItem)
            } else {
                player = AVPlayer(playerItem: playerItem)
                setupTimeObserver()
            }
        }
    }
}

// MARK: - Error Types

enum VideoError: LocalizedError {
    case compositionCreationFailed
    case noVideoTrack
    case trackCreationFailed
    case noComposition
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .compositionCreationFailed:
            return "Failed to create video composition"
        case .noVideoTrack:
            return "No video track found in asset"
        case .trackCreationFailed:
            return "Failed to create composition track"
        case .noComposition:
            return "No composition available for export"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed:
            return "Failed to export video"
        case .exportCancelled:
            return "Video export was cancelled"
        }
    }
}
