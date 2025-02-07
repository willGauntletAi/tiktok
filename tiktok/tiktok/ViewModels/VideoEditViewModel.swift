@preconcurrency import CoreImage
@preconcurrency import AVFoundation
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
                updatePlayer()
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
        clips.remove(at: index)
        if selectedClipIndex == index {
            selectedClipIndex = clips.isEmpty ? nil : min(index, clips.count - 1)
        }
        // Update player with remaining clips
        Task {
            await setupPlayerWithComposition()
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
            case .exporting(let progress):
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
        guard !clips.isEmpty else {
            print("No clips to split")
            return
        }
        
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
        
        guard let composition = composition else {
            print("No composition available for splitting")
            return
        }
        
        let splitTime = CMTime(seconds: time, preferredTimescale: 600)
        let tracks = composition.tracks
        print("Found \(tracks.count) tracks to split")
        
        do {
            // Split each track at the specified time
            for (index, track) in tracks.enumerated() {
                print("Processing track \(index + 1) of \(tracks.count)")
                guard let segment = track.segment(forTrackTime: splitTime) else {
                    print("No segment found for track \(index + 1)")
                    continue
                }
                
                print("Creating new track for split")
                guard let newTrack = composition.addMutableTrack(
                    withMediaType: track.mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    print("Failed to create new track for split")
                    continue
                }
                
                let timeMapping = segment.timeMapping
                
                print("Moving second part to new track")
                try newTrack.insertTimeRange(
                    CMTimeRange(start: splitTime, end: timeMapping.target.end),
                    of: track,
                    at: splitTime
                )
                
                print("Trimming original track")
                track.removeTimeRange(
                    CMTimeRange(start: splitTime, end: timeMapping.target.end)
                )
            }
            
            print("Updating UI after split")
            await MainActor.run {
                if let selectedIndex = selectedClipIndex,
                   selectedIndex < clips.count {
                    var originalClip = clips[selectedIndex]
                    let splitDuration = originalClip.endTime - time
                    
                    print("Updating original clip duration")
                    originalClip.endTime = time
                    clips[selectedIndex] = originalClip
                    
                    print("Creating new clip for split part")
                    let newClip = VideoClip(
                        asset: originalClip.asset,
                        startTime: time,
                        endTime: time + splitDuration,
                        thumbnail: originalClip.thumbnail
                    )
                    
                    print("Inserting new clip")
                    clips.insert(newClip, at: selectedIndex + 1)
                }
                
                updatePlayer()
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
