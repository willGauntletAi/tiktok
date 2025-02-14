@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import CoreMedia
import FirebaseFunctions
import SwiftUI
import UIKit

enum VideoError: Error {
    case noVideoTrack
    case noComposition
    case exportSessionCreationFailed
    case exportFailed
}

struct EditorState {
    let clips: [VideoClip]
    let selectedClipIndex: Int?
}

enum EditAction {
    case addClip(clipId: Int)
    case deleteClip(index: Int)
    case moveClip(from: Int, to: Int)
    case swapClips(index: Int)
    case splitClip(time: Double)
    case trimClip(clipId: Int, startTime: Double, endTime: Double)
    case updateVolume(clipId: Int, volume: Double)
    case updateZoom(clipId: Int, config: ZoomConfig?)
}

struct EditHistoryEntry: Identifiable {
    let id = UUID()
    let title: String
    let timestamp: Date
    let state: EditorState
    let action: EditAction
    let prompt: String?
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

    // Edit history management
    @Published private(set) var editHistory: [EditHistoryEntry] = []
    @Published private(set) var currentHistoryIndex: Int = -1

    // Initialize without UndoManager
    init() {
        // No need to call updateEditHistory() on init anymore
    }

    private func addHistoryEntry(title: String, action: EditAction, prompt: String? = nil) {
        // If we're not at the end of the history, remove all future entries
        if currentHistoryIndex < editHistory.count - 1 {
            editHistory.removeSubrange((currentHistoryIndex + 1)...)
        }

        // Create new state snapshot
        let newState = EditorState(
            clips: clips,
            selectedClipIndex: selectedClipIndex
        )

        // Add the new entry
        let newEntry = EditHistoryEntry(
            title: title,
            timestamp: Date(),
            state: newState,
            action: action,
            prompt: prompt
        )
        editHistory.append(newEntry)
        currentHistoryIndex = editHistory.count - 1
    }

    func undo(to targetIndex: Int? = nil) async {
        // If no target index is provided, undo the most recent action
        let indexToUndoTo = targetIndex ?? (currentHistoryIndex - 1)

        guard indexToUndoTo >= -1 else { return }

        if indexToUndoTo == -1 {
            // Reset to empty state but keep history
            clips.removeAll()
            selectedClipIndex = nil
            composition = nil
            totalDuration = 0
            currentHistoryIndex = -1

            // Reset player
            if let observer = timeObserver {
                _player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            _player?.pause()
            _player = nil
            playerItem = nil
        } else {
            // Move to the target state
            currentHistoryIndex = indexToUndoTo
            await applyState(editHistory[indexToUndoTo].state)
        }
    }

    func redo(to targetIndex: Int? = nil) async {
        // If no target index is provided, redo the next action
        let indexToRedoTo = targetIndex ?? (currentHistoryIndex + 1)

        guard indexToRedoTo < editHistory.count else { return }

        // When redoing from empty state (-1), we need to ensure we fully restore the state
        if currentHistoryIndex == -1 {
            // Reset player state first
            if let observer = timeObserver {
                _player?.removeTimeObserver(observer)
                timeObserver = nil
            }
            _player?.pause()
            _player = nil
            playerItem = nil

            // Apply the state first
            let targetState = editHistory[indexToRedoTo].state
            clips = targetState.clips
            selectedClipIndex = targetState.selectedClipIndex
            currentHistoryIndex = indexToRedoTo

            // Create a new composition
            let newComposition = AVMutableComposition()
            composition = newComposition

            // Then rebuild everything if we have clips
            if !clips.isEmpty {
                try? await rebuildComposition()
            }
        } else {
            // Normal redo operation
            currentHistoryIndex = indexToRedoTo
            await applyState(editHistory[indexToRedoTo].state)
        }
    }

    private func applyState(_ state: EditorState) async {
        print("Applying editor state with \(state.clips.count) clips")

        // First update the basic state
        clips = state.clips
        selectedClipIndex = state.selectedClipIndex

        // Reset player state first if needed
        if let observer = timeObserver {
            _player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        _player?.pause()
        _player = nil
        playerItem = nil

        // Only rebuild composition if we have clips
        if !clips.isEmpty {
            // Log pose detection state for debugging
            for (index, clip) in clips.enumerated() {
                print("Clip \(index) pose detection status: \(clip.poseDetectionStatus)")
                print("  - Pose results: \(clip.poseResults?.count ?? 0)")
                print("  - Detected sets: \(clip.detectedSets?.count ?? 0)")
            }

            await setupPlayerWithComposition()
        } else {
            // Reset other state when going to empty state
            composition = nil
            totalDuration = 0
        }

        print("State application complete")
    }

    // Remove UndoManager-related code from all action methods
    func updateClipTrim(startTime: Double, endTime: Double) {
        guard let clip = selectedClip,
              let index = selectedClipIndex
        else { return }

        print("🔄 Trimming clip \(clip.id) using split and remove:")
        print("  Original state:")
        print("    - Composition times: \(clip.startTime) to \(clip.endTime)")
        print("    - Asset times: \(clip.assetStartTime) to \(clip.assetStartTime + clip.assetDuration)")
        print("    - Target trim: \(startTime) to \(endTime)")

        Task {
                // Calculate how much time we'll remove from the start (if any)
                let startTimeRemoval = startTime > clip.startTime ? startTime - clip.startTime : 0
                print("  Start time removal: \(String(format: "%.2f", startTimeRemoval))s")

                // Adjust the end split point by the amount we'll remove from the start
                let adjustedEndTime = endTime - startTimeRemoval
                print("  Adjusted end time: \(String(format: "%.2f", adjustedEndTime))s")

                // Keep track of our target clip's ID since the index will change
                let targetClipId = clip.id
                var currentIndex = index

                // Step 1: If we need to trim the start, split at the new start point and remove the first part
                if startTime > clip.startTime {
                    print("  Splitting at start point: \(startTime)")
                    await splitClip(at: startTime)
                    
                    // Find where our target clip went after the split
                    if let newIndex = clips.firstIndex(where: { $0.id == targetClipId }) {
                        print("  Target clip moved to index \(newIndex)")
                        currentIndex = newIndex
                    } else {
                        print("❌ Lost track of target clip after split")
                        return
                    }
                    
                    // Remove the first part (which is one index before our current position)
                    let deleteIndex = currentIndex - 1
                    if deleteIndex >= 0 && deleteIndex < clips.count {
                        print("  Removing first part at index \(deleteIndex)")
                        deleteClip(at: deleteIndex)
                        // After deletion, our target clip moved back one position
                        currentIndex -= 1
                    }
                }

                // Verify we can still find our clip
                guard let finalIndex = clips.firstIndex(where: { $0.id == targetClipId }) else {
                    print("❌ Lost track of target clip before end trim")
                    return
                }
                currentIndex = finalIndex
                
                // Get the updated clip state
                if clips[safe: currentIndex] == nil {
                    print("❌ Target clip index out of bounds")
                    return
                }

                // Step 2: If we need to trim the end, split at the adjusted end time and remove the second part
                if endTime < clip.endTime {
                    print("  Splitting at adjusted end point: \(adjustedEndTime)")
                    await splitClip(at: adjustedEndTime)
                    
                    // Find our clip's position again after the split
                    if let newIndex = clips.firstIndex(where: { $0.id == targetClipId }) {
                        print("  Target clip at index \(newIndex)")
                        currentIndex = newIndex
                        
                        // Remove the second part (which is right after our current position)
                        if clips.count > currentIndex + 1 {
                            print("  Removing second part at index \(currentIndex + 1)")
                            deleteClip(at: currentIndex + 1)
                        }
                    } else {
                        print("❌ Lost track of target clip after end split")
                        return
                    }
                }

                print("  Final state:")
                if let finalClip = clips.first(where: { $0.id == targetClipId }) {
                    print("    - Composition times: \(finalClip.startTime) to \(finalClip.endTime)")
                    print("    - Asset times: \(finalClip.assetStartTime) to \(finalClip.assetStartTime + finalClip.assetDuration)")
                }

                // Update player position
                await player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
    }

    // ... similar changes for other action methods ...

    private func setupVideoComposition(for composition: AVMutableComposition, clips: [VideoClip]) async throws -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // Set color properties to maintain correct color appearance
        videoComposition.colorPrimaries = kCVImageBufferColorPrimaries_ITU_R_709_2 as String
        videoComposition.colorYCbCrMatrix = kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String
        videoComposition.colorTransferFunction = kCVImageBufferTransferFunction_ITU_R_709_2 as String

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var currentTime = CMTime.zero

        // Get all composition tracks
        let compositionTracks = composition.tracks(withMediaType: .video)
        print("Number of composition tracks: \(compositionTracks.count)")

        // Process each clip
        for (index, clip) in clips.enumerated() {
            if let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first {
                // Create instruction for this clip
                let instruction = AVMutableVideoCompositionInstruction()
                let clipDuration = CMTime(seconds: clip.assetDuration, preferredTimescale: 600)
                instruction.timeRange = CMTimeRange(start: currentTime, duration: clipDuration)

                // Create layer instructions for all tracks, but only make the current one visible
                var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []

                for (trackIndex, compositionTrack) in compositionTracks.enumerated() {
                    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)

                    // Get the original transform and properties for the current clip's track
                    let transform = try await videoTrack.load(.preferredTransform)
                    let naturalSize = try await videoTrack.load(.naturalSize)

                    if trackIndex == index {
                        // This is the current clip's track
                        layerInstruction.setTransform(transform, at: currentTime)
                        layerInstruction.setOpacity(1.0, at: currentTime)

                        // Handle zoom effect if configured
                        if let zoomConfig = clip.zoomConfig {
                            try await configureZoomEffect(
                                for: layerInstruction,
                                clip: clip,
                                transform: transform,
                                naturalSize: naturalSize,
                                currentTime: currentTime,
                                zoomConfig: zoomConfig
                            )
                        } else {
                            layerInstruction.setTransform(transform, at: currentTime)
                            layerInstruction.setOpacity(1.0, at: currentTime)
                        }
                    } else {
                        // Hide other tracks during this time range
                        layerInstruction.setOpacity(0.0, at: currentTime)
                    }

                    layerInstructions.append(layerInstruction)
                }

                instruction.layerInstructions = layerInstructions
                instructions.append(instruction)

                // Set video composition render size if not already set
                if videoComposition.renderSize == .zero {
                    try await configureRenderSize(videoComposition: videoComposition, videoTrack: videoTrack)
                }

                currentTime = currentTime + clipDuration
            }
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    private func configureZoomEffect(
        for layerInstruction: AVMutableVideoCompositionLayerInstruction,
        clip: VideoClip,
        transform: CGAffineTransform,
        naturalSize: CGSize,
        currentTime: CMTime,
        zoomConfig: ZoomConfig
    ) async throws {
        // Calculate zoom transform while preserving color properties
        let scale: CGFloat = 1.5
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)

        // If we have a focused joint and pose results, prepare for dynamic tracking
        if let focusedJoint = zoomConfig.focusedJoint,
           let poseResults = clip.poseResults,
           !poseResults.isEmpty
        {
            print("🏃‍♂️ Starting joint tracking for \(focusedJoint.displayName)")
            print("  ├─ Total pose results: \(poseResults.count)")
            print("  ├─ Time range: \(poseResults.first?.timestamp ?? 0) to \(poseResults.last?.timestamp ?? 0)")

            // Function to get transform for a specific time
            let getTransformForTime = { (time: Double) -> CGAffineTransform in
                // Find the pose results that bracket this time
                let timestamp = clip.assetStartTime + (time - clip.startTime)
                print("🎯 Getting transform for time: \(time)")
                print("  ├─ Composition time: \(time)")
                print("  ├─ Asset time: \(timestamp)")

                // Find high confidence keyframes before and after this timestamp
                let highConfidenceResults = poseResults
                    .filter { result in
                        guard let joint = result.keypoints.first(where: { $0.type == focusedJoint }) else { return false }
                        return joint.confidence > 0.5 // Only use high confidence frames
                    }
                    .sorted { $0.timestamp < $1.timestamp }

                // Find the closest keyframes before and after our target time
                let previousKeyframe = highConfidenceResults.last { $0.timestamp <= timestamp }
                let nextKeyframe = highConfidenceResults.first { $0.timestamp > timestamp }

                print("📍 Found keyframes:")
                if let prev = previousKeyframe {
                    print("  ├─ Previous at: \(prev.timestamp)")
                }
                if let next = nextKeyframe {
                    print("  └─ Next at: \(next.timestamp)")
                }

                // If we have both keyframes, interpolate between them
                if let prevFrame = previousKeyframe,
                   let nextFrame = nextKeyframe,
                   let prevJoint = prevFrame.keypoints.first(where: { $0.type == focusedJoint }),
                   let nextJoint = nextFrame.keypoints.first(where: { $0.type == focusedJoint })
                {
                    // Calculate interpolation factor
                    let progress = (timestamp - prevFrame.timestamp) / (nextFrame.timestamp - prevFrame.timestamp)
                    let clampedProgress = max(0, min(1, progress))

                    // Interpolate joint positions
                    let jointX = prevJoint.position.x + (nextJoint.position.x - prevJoint.position.x) * CGFloat(clampedProgress)
                    let jointY = prevJoint.position.y + (nextJoint.position.y - prevJoint.position.y) * CGFloat(clampedProgress)

                    print("  ├─ Interpolating between positions:")
                    print("  │  ├─ Previous: (\(prevJoint.position.x), \(prevJoint.position.y))")
                    print("  │  ├─ Next: (\(nextJoint.position.x), \(nextJoint.position.y))")
                    print("  │  ├─ Progress: \(clampedProgress)")
                    print("  │  └─ Result: (\(jointX), \(jointY))")

                    // Calculate transform for interpolated position
                    // Note: Invert y-coordinate (1 - jointY) since pose detection uses top-left origin
                    // and we need bottom-left origin for Core Graphics
                    let centerOffsetX = jointX * naturalSize.width - naturalSize.width / 2
                    let centerOffsetY = (1 - jointY) * naturalSize.height - naturalSize.height / 2

                    // Calculate the maximum allowed translation that would keep the scaled video within bounds
                    // When scaled, the video is larger than the view by (scale - 1) * size
                    // The maximum translation should keep the scaled edges within the original bounds
                    let scaledWidth = naturalSize.width * scale
                    let scaledHeight = naturalSize.height * scale

                    // Calculate the maximum translation that would keep the scaled content within bounds
                    // This is half the difference between the scaled size and the original size
                    let maxOffsetX = (scaledWidth - naturalSize.width) / 2
                    let maxOffsetY = (scaledHeight - naturalSize.height) / 2

                    // Calculate the minimum and maximum allowed translations
                    // These ensure that we don't show empty space on either side
                    let minTx = -maxOffsetX
                    let maxTx = maxOffsetX
                    let minTy = -maxOffsetY
                    let maxTy = maxOffsetY

                    // Clamp the translation to keep the scaled video within bounds
                    let clampedTx = max(minTx, min(maxTx, -centerOffsetX))
                    let clampedTy = max(minTy, min(maxTy, -centerOffsetY))

                    // Apply scale first, then translation
                    return transform
                        .concatenating(scaleTransform)
                        .concatenating(CGAffineTransform(translationX: clampedTx, y: clampedTy))
                }
                // If we only have a previous keyframe, use that
                else if let prevFrame = previousKeyframe,
                        let prevJoint = prevFrame.keypoints.first(where: { $0.type == focusedJoint })
                {
                    let centerOffsetX = prevJoint.position.x * naturalSize.width - naturalSize.width / 2
                    let centerOffsetY = (1 - prevJoint.position.y) * naturalSize.height - naturalSize.height / 2

                    let maxOffsetX = (naturalSize.width * (scale - 1)) / 2
                    let maxOffsetY = (naturalSize.height * (scale - 1)) / 2

                    let clampedTx = max(-maxOffsetX, min(maxOffsetX, -centerOffsetX))
                    let clampedTy = max(-maxOffsetY, min(maxOffsetY, -centerOffsetY))

                    return transform
                        .concatenating(scaleTransform)
                        .concatenating(CGAffineTransform(translationX: clampedTx, y: clampedTy))
                }
                // If we only have a next keyframe, use that
                else if let nextFrame = nextKeyframe,
                        let nextJoint = nextFrame.keypoints.first(where: { $0.type == focusedJoint })
                {
                    let centerOffsetX = nextJoint.position.x * naturalSize.width - naturalSize.width / 2
                    let centerOffsetY = (1 - nextJoint.position.y) * naturalSize.height - naturalSize.height / 2

                    let maxOffsetX = (naturalSize.width * (scale - 1)) / 2
                    let maxOffsetY = (naturalSize.height * (scale - 1)) / 2

                    let clampedTx = max(-maxOffsetX, min(maxOffsetX, -centerOffsetX))
                    let clampedTy = max(-maxOffsetY, min(maxOffsetY, -centerOffsetY))

                    return transform
                        .concatenating(scaleTransform)
                        .concatenating(CGAffineTransform(translationX: clampedTx, y: clampedTy))
                }

                // Fallback to center zoom if no valid keyframes
                let tx = (naturalSize.width * (scale - 1)) / 2
                let ty = (naturalSize.height * (scale - 1)) / 2
                return transform
                    .concatenating(scaleTransform)
                    .concatenating(CGAffineTransform(translationX: -tx, y: -ty))
            }

            try await configureJointTrackedZoom(
                for: layerInstruction,
                clip: clip,
                transform: transform,
                currentTime: currentTime,
                zoomConfig: zoomConfig,
                getTransformForTime: getTransformForTime
            )
        } else {
            try await configureCenterBasedZoom(
                for: layerInstruction,
                clip: clip,
                transform: transform,
                naturalSize: naturalSize,
                currentTime: currentTime,
                zoomConfig: zoomConfig,
                scale: scale,
                scaleTransform: scaleTransform
            )
        }
    }

    private func configureJointTrackedZoom(
        for layerInstruction: AVMutableVideoCompositionLayerInstruction,
        clip: VideoClip,
        transform: CGAffineTransform,
        currentTime: CMTime,
        zoomConfig: ZoomConfig,
        getTransformForTime: @escaping (Double) -> CGAffineTransform
    ) async throws {
        // Use a fixed interval of 1/30th second for smooth motion
        let interval = 1.0 / 30.0
        layerInstruction.setOpacity(1.0, at: currentTime)

        // Calculate the full tracking period
        let trackingStartTime = clip.startTime + zoomConfig.startZoomIn
        let trackingEndTime = if let zoomOutComplete = zoomConfig.zoomOutComplete {
            clip.startTime + zoomOutComplete
        } else if let startZoomOut = zoomConfig.startZoomOut {
            clip.startTime + startZoomOut
        } else {
            clip.endTime
        }

        print("🔍 Setting up joint tracking:")
        print("  ├─ Start time: \(trackingStartTime)")
        print("  └─ End time: \(trackingEndTime)")

        let duration = trackingEndTime - trackingStartTime
        let keyframeCount = Int(ceil(duration / interval))

        print("⏱️ Tracking configuration:")
        print("  ├─ Duration: \(duration)s")
        print("  ├─ Interval: \(interval)s")
        print("  ├─ Keyframe count: \(keyframeCount)")
        print("  ├─ Zoom in complete: \(String(describing: zoomConfig.zoomInComplete))")
        print("  ├─ Start zoom out: \(String(describing: zoomConfig.startZoomOut))")
        print("  └─ Zoom out complete: \(String(describing: zoomConfig.zoomOutComplete))")

        print("🎬 Starting keyframe generation")

        // Generate all keyframes in a single pass
        for i in 0 ..< keyframeCount {
            let time = trackingStartTime + interval * Double(i)
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            // Determine which phase of the zoom effect we're in
            let currentTransform: CGAffineTransform

            if let zoomInComplete = zoomConfig.zoomInComplete,
               time <= clip.startTime + zoomInComplete
            {
                // During zoom in - interpolate between identity and tracked
                let progress = (time - trackingStartTime) / (zoomInComplete - zoomConfig.startZoomIn)
                currentTransform = transform.interpolating(
                    to: getTransformForTime(time),
                    amount: progress
                )
            } else if let startZoomOut = zoomConfig.startZoomOut,
                      let zoomOutComplete = zoomConfig.zoomOutComplete,
                      time >= clip.startTime + startZoomOut
            {
                // During zoom out - interpolate between tracked and identity
                let progress = (time - (clip.startTime + startZoomOut)) / (zoomOutComplete - startZoomOut)
                currentTransform = getTransformForTime(time).interpolating(
                    to: transform,
                    amount: progress
                )
            } else {
                // During full zoom - use tracked transform
                currentTransform = getTransformForTime(time)
            }

            layerInstruction.setTransform(currentTransform, at: cmTime)
            layerInstruction.setOpacity(1.0, at: cmTime)
        }

        // Set final transform state if we ended before clip end
        if trackingEndTime < clip.endTime {
            layerInstruction.setTransform(
                transform,
                at: CMTime(seconds: trackingEndTime, preferredTimescale: 600)
            )
            layerInstruction.setOpacity(1.0, at: CMTime(seconds: trackingEndTime, preferredTimescale: 600))
        }

        print("✅ Completed keyframe generation")
    }

    private func configureCenterBasedZoom(
        for layerInstruction: AVMutableVideoCompositionLayerInstruction,
        clip: VideoClip,
        transform: CGAffineTransform,
        naturalSize: CGSize,
        currentTime: CMTime,
        zoomConfig: ZoomConfig,
        scale: CGFloat,
        scaleTransform: CGAffineTransform
    ) async throws {
        // Fallback to center-based zoom if no joint tracking
        let tx = (naturalSize.width * (scale - 1)) / 2
        let ty = (naturalSize.height * (scale - 1)) / 2
        let centeringTransform = CGAffineTransform(translationX: -tx, y: -ty)

        let zoomTransform = transform
            .concatenating(centeringTransform)
            .concatenating(scaleTransform)

        // Handle zoom in
        let zoomInStart = CMTime(seconds: clip.startTime + zoomConfig.startZoomIn, preferredTimescale: 600)
        layerInstruction.setOpacity(1.0, at: currentTime)

        if let zoomInComplete = zoomConfig.zoomInComplete {
            let zoomInEnd = CMTime(seconds: clip.startTime + zoomInComplete, preferredTimescale: 600)
            layerInstruction.setTransformRamp(
                fromStart: transform,
                toEnd: zoomTransform,
                timeRange: CMTimeRange(start: zoomInStart, end: zoomInEnd)
            )
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
                layerInstruction.setTransformRamp(
                    fromStart: zoomTransform,
                    toEnd: transform,
                    timeRange: CMTimeRange(start: zoomOutStart, end: zoomOutEnd)
                )
                layerInstruction.setOpacity(1.0, at: zoomOutStart)
                layerInstruction.setOpacity(1.0, at: zoomOutEnd)
            } else {
                layerInstruction.setTransform(transform, at: zoomOutStart)
                layerInstruction.setOpacity(1.0, at: zoomOutStart)
            }
        }
    }

    private func configureRenderSize(videoComposition: AVMutableVideoComposition, videoTrack: AVAssetTrack) async throws {
        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)

        let isVideoPortrait = transform.a == 0 && abs(transform.b) == 1
        videoComposition.renderSize = CGSize(
            width: isVideoPortrait ? naturalSize.height : naturalSize.width,
            height: isVideoPortrait ? naturalSize.width : naturalSize.height
        )
    }

    @MainActor
    func addClip(from url: URL) async throws {
        isProcessing = true

        do {
            print("Adding clip from URL: \(url)")

            // Create asset with conservative memory options
            let options: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: true,
                AVURLAssetAllowsCellularAccessKey: true,
            ]

            let asset = AVURLAsset(url: url, options: options)

            // Verify we can load the tracks before proceeding
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else {
                throw VideoError.noVideoTrack
            }

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
            let currentTime = CMTime(seconds: totalDuration, preferredTimescale: 600)

            let assetDuration = try await asset.load(.duration)
            print("Asset duration: \(assetDuration.seconds) seconds")

            // Create a unique track ID for this clip
            let trackID = clips.count + 1

            print("Adding video track to composition...")
            // Add video track with unique ID
            let compositionVideoTrack = newComposition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: CMPersistentTrackID(trackID)
            )

            try compositionVideoTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: videoTrack,
                at: currentTime
            )

            // Add audio track if available
            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                print("Adding audio track to composition...")
                let compositionAudioTrack = newComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: CMPersistentTrackID(trackID + 1000)
                )

                try compositionAudioTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: assetDuration),
                    of: audioTrack,
                    at: currentTime
                )
            }

            // Wait for thumbnail generation to complete
            print("Waiting for thumbnail generation...")
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

            print("Adding clip to model...")
            // Add clip and start pose detection
            clips.append(newClip)

            // Update state before starting pose detection
            composition = newComposition
            totalDuration = (currentTime + assetDuration).seconds
            selectedClipIndex = clips.count - 1 // Set the newly added clip as selected

            print("Setting up video composition...")
            // Create video composition and update player
            let videoComposition = try await setupVideoComposition(for: newComposition, clips: clips)
            updatePlayer(with: videoComposition)

            // Add to history
            addHistoryEntry(title: "Add Clip", action: .addClip(clipId: clips.last?.id ?? 0))

            // Start pose detection after everything else is set up
            startPoseDetection(for: newClip)

            // Clean up the original temporary file if needed
            if url.path.contains("/tmp/") {
                try? FileManager.default.removeItem(at: url)
            }

        } catch {
            print("Error adding clip: \(error.localizedDescription)")
            if let avError = error as? AVError {
                print("AVError details: \(avError.localizedDescription)")
                print("AVError code: \(avError.code.rawValue)")
                print("AVError user info: \(avError.userInfo)")
            }
            throw error
        }

        isProcessing = false
    }

    private func updatePlayer(with videoComposition: AVMutableVideoComposition? = nil) {
        guard let composition = composition else { return }

        Task { @MainActor in
            // Create player item with composition
            let playerItem = AVPlayerItem(asset: composition)

            // Apply video composition if provided
            if let videoComposition = videoComposition {
                playerItem.videoComposition = videoComposition
            }

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

    func updateClipVolume(_ volume: Double) {
        guard var clip = selectedClip,
              let index = selectedClipIndex
        else { return }

        clip.volume = volume
        clips[index] = clip

        // Add to history
        addHistoryEntry(
            title: "Change Volume",
            action: .updateVolume(clipId: clip.id, volume: volume)
        )

        updatePlayerVolume()
    }

    func moveClip(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)

        if let selected = selectedClipIndex,
           let sourceFirst = source.first
        {
            selectedClipIndex = sourceFirst < selected ? (selected - 1) : (selected + 1)
        }

        // Add to history
        addHistoryEntry(
            title: "Move Clip",
            action: .moveClip(from: source.first ?? 0, to: destination)
        )

        // Update player with new clip order
        Task {
            await setupPlayerWithComposition()
        }
    }

    func deleteClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        
        print("🗑️ Deleting clip at index \(index)")
        let clip = clips[index]
        print("  Clip duration: \(clip.endTime - clip.startTime)")
        
        // Remove the clip
        clips.remove(at: index)
        
        // Adjust the start times of all subsequent clips
        let removedDuration = clip.endTime - clip.startTime
        for i in index..<clips.count {
            var adjustedClip = clips[i]
            adjustedClip.startTime -= removedDuration
            adjustedClip.endTime -= removedDuration
            clips[i] = adjustedClip
        }
        
        // Add to history
        addHistoryEntry(
            title: "Delete Clip",
            action: .deleteClip(index: index)
        )
        
        // Update the selected clip index if needed
        if selectedClipIndex == index {
            selectedClipIndex = clips.isEmpty ? nil : min(index, clips.count - 1)
        } else if let selected = selectedClipIndex, selected > index {
            selectedClipIndex = selected - 1
        }
        
        // Update the composition
        Task {
            await setupPlayerWithComposition()
        }
    }

    func export() async throws -> URL {
        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

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
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        // Modern async/await export with progress monitoring
        for try await state in exportSession.states() {
            switch state {
            case .waiting:
                print("Export waiting...")
            case let .exporting(progress):
                print("Export progress: \(Int(progress.fractionCompleted * 100))%")
            case .pending:
                print("Export pending...")
            @unknown default:
                print("Unknown export state encountered: \(state)")
            }
        }

        // After the export completes, check the status
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

        // If there are no clips, reset the player and return early
        if clips.isEmpty {
            await MainActor.run {
                // Reset everything
                self.composition = nil
                self.totalDuration = 0
                self.currentPosition = 0

                // Clean up player
                if let observer = timeObserver {
                    player?.removeTimeObserver(observer)
                    timeObserver = nil
                }
                player?.pause()
                player = nil
                playerItem = nil
            }
            return
        }

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

        // Only setup video composition if we have clips
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
        editHistory.removeAll()
        currentHistoryIndex = -1
    }

    private func setupPlayerWithComposition() async {
        print("Starting setupPlayerWithComposition")

        // Create new composition if none exists
        if composition == nil {
            composition = AVMutableComposition()
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

        // Add to history
        addHistoryEntry(
            title: "Swap Clips",
            action: .swapClips(index: index)
        )

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
        print("🔄 Splitting clip at absolute time: \(time)")
        
        // Find which clip contains this time by accumulating durations
        var accumulatedTime = 0.0
        var targetIndex: Int?
        var relativeTime: Double = 0.0
        
        for (index, clip) in clips.enumerated() {
            let clipDuration = clip.endTime - clip.startTime
            if time > accumulatedTime && time < accumulatedTime + clipDuration {
                targetIndex = index
                relativeTime = time - accumulatedTime
                break
            }
            accumulatedTime += clipDuration
        }
        
        guard let index = targetIndex else {
            print("❌ No clip found at time \(time)")
            return
        }
        
        let clip = clips[index]
        print("  Found clip \(clip.id) at index \(index)")
        print("  Clip range: \(clip.startTime) to \(clip.endTime)")
        print("  Relative split time: \(relativeTime)")
        
        do {
            // Create a new composition for the split operation
            let splitComposition = AVMutableComposition()
            
            // Get the video track from the original asset
            guard let videoTrack = try await clip.asset.loadTracks(withMediaType: .video).first else {
                print("❌ No video track found")
                return
            }
            
            // Create two video tracks in the new composition
            let firstVideoTrack = splitComposition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            
            let secondVideoTrack = splitComposition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            
            // Calculate time ranges for the split
            let splitPoint = CMTime(seconds: relativeTime, preferredTimescale: 600)
            let firstRange = CMTimeRange(
                start: CMTime(seconds: clip.assetStartTime, preferredTimescale: 600),
                end: CMTime(seconds: clip.assetStartTime + relativeTime, preferredTimescale: 600)
            )
            let secondRange = CMTimeRange(
                start: CMTime(seconds: clip.assetStartTime + relativeTime, preferredTimescale: 600),
                end: CMTime(seconds: clip.assetStartTime + clip.assetDuration, preferredTimescale: 600)
            )
            
            // Insert the video segments
            try firstVideoTrack?.insertTimeRange(firstRange, of: videoTrack, at: .zero)
            try secondVideoTrack?.insertTimeRange(secondRange, of: videoTrack, at: .zero)
            
            // Handle audio tracks if they exist
            if let audioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
                let firstAudioTrack = splitComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                
                let secondAudioTrack = splitComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                
                try firstAudioTrack?.insertTimeRange(firstRange, of: audioTrack, at: .zero)
                try secondAudioTrack?.insertTimeRange(secondRange, of: audioTrack, at: .zero)
            }
            
            // Generate thumbnails for both parts
            let imageGenerator = AVAssetImageGenerator(asset: clip.asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)
            
            let firstThumbnailTime = CMTime(seconds: clip.assetStartTime + 0.03, preferredTimescale: 600)
            let secondThumbnailTime = CMTime(seconds: clip.assetStartTime + relativeTime + 0.03, preferredTimescale: 600)
            
            let firstImage = try await imageGenerator.image(at: firstThumbnailTime)
            let secondImage = try await imageGenerator.image(at: secondThumbnailTime)
            
            // Create the two new clips
            var firstClip = VideoClip(
                asset: clip.asset,
                startTime: clip.startTime,
                endTime: clip.startTime + relativeTime,
                thumbnail: UIImage(cgImage: firstImage.image),
                assetStartTime: clip.assetStartTime,
                assetDuration: relativeTime
            )
            
            var secondClip = VideoClip(
                asset: clip.asset,
                startTime: clip.startTime + relativeTime,
                endTime: clip.endTime,
                thumbnail: UIImage(cgImage: secondImage.image),
                assetStartTime: clip.assetStartTime + relativeTime,
                assetDuration: clip.assetDuration - relativeTime
            )
            
            // Copy over pose detection results and split them between the clips
            if let poseResults = clip.poseResults {
                firstClip.poseResults = poseResults.filter { result in
                    let relativeTime = result.timestamp - firstClip.assetStartTime
                    return relativeTime >= 0 && relativeTime <= firstClip.assetDuration
                }
                
                secondClip.poseResults = poseResults.filter { result in
                    let relativeTime = result.timestamp - secondClip.assetStartTime
                    return relativeTime >= 0 && relativeTime <= secondClip.assetDuration
                }
            }
            
            // Copy over detected sets and split them between the clips
            if let detectedSets = clip.detectedSets {
                firstClip.detectedSets = detectedSets.filter { set in
                    let relativeStartTime = set.startTime - firstClip.assetStartTime
                    let relativeEndTime = set.endTime - firstClip.assetStartTime
                    return relativeStartTime >= 0 && relativeEndTime <= firstClip.assetDuration
                }
                
                secondClip.detectedSets = detectedSets.filter { set in
                    let relativeStartTime = set.startTime - secondClip.assetStartTime
                    let relativeEndTime = set.endTime - secondClip.assetStartTime
                    return relativeStartTime >= 0 && relativeEndTime <= secondClip.assetDuration
                }
            }
            
            // Set pose detection status for both clips
            firstClip.poseDetectionStatus = clip.poseDetectionStatus
            secondClip.poseDetectionStatus = clip.poseDetectionStatus
            
            // Update the clips array
            await MainActor.run {
                clips.remove(at: index)
                clips.insert(secondClip, at: index)
                clips.insert(firstClip, at: index)
                
                // Add to history
                addHistoryEntry(
                    title: "Split Clip",
                    action: .splitClip(time: time)
                )
            }
            
            // Rebuild the composition
            await setupPlayerWithComposition()
            
        } catch {
            print("❌ Error splitting clip: \(error.localizedDescription)")
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

        // Add to history
        addHistoryEntry(
            title: config == nil ? "Remove Zoom" : "Add Zoom",
            action: .updateZoom(clipId: updatedClip.id, config: config)
        )

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
                updatedClip.detectedSets = sets
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

    deinit {
        // Clean up time observer
        if let observer = timeObserver {
            _player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Clean up player
        _player?.pause()
        _player = nil

        // Cancel any ongoing pose detection tasks
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for clip in self.clips {
                await self.poseDetectionService.cancelDetection(for: clip.id)
            }
        }

        // Clean up temporary files
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir)
    }

    func requestAIEditSuggestion(prompt: String) async {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        do {
            print("\n🎬 AI Edit Suggestion Request Log")
            print("================================")
            print("📝 User Prompt:", prompt)

            // Wait for all pose detection to complete
            print("\n⏳ Waiting for Pose Detection")
            print("----------------------------")
            for (index, clip) in clips.enumerated() {
                while clip.poseDetectionStatus == .pending || clip.poseDetectionStatus == .inProgress {
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    print("  ⌛️ Clip \(index) (ID: \(clip.id)): Still processing...")
                }

                if case let .failed(error) = clip.poseDetectionStatus {
                    print("  ⚠️ Clip \(index) (ID: \(clip.id)): Pose detection failed - \(error.localizedDescription)")
                } else {
                    print("  ✅ Clip \(index) (ID: \(clip.id)): Processing complete")
                }
            }

            // Log clips state
            print("\n📊 Current Clips State")
            print("--------------------")
            for (index, clip) in clips.enumerated() {
                print("\n  🎥 Clip \(index):")
                print("    • ID: \(clip.id)")
                print("    • Duration: \(String(format: "%.2f", clip.endTime - clip.startTime))s")
                print("    • Timeline Position: \(String(format: "%.2f", clip.startTime))s → \(String(format: "%.2f", clip.endTime))s")
                print("    • Asset Range: \(String(format: "%.2f", clip.assetStartTime))s → \(String(format: "%.2f", clip.assetStartTime + clip.assetDuration))s")
                
                if let config = clip.zoomConfig {
                    print("    • Zoom Configuration:")
                    print("      - Start Zoom In: \(String(format: "%.2f", config.startZoomIn))s")
                    if let complete = config.zoomInComplete {
                        print("      - Zoom In Complete: \(String(format: "%.2f", complete))s")
                    }
                    if let start = config.startZoomOut {
                        print("      - Start Zoom Out: \(String(format: "%.2f", start))s")
                    }
                    if let complete = config.zoomOutComplete {
                        print("      - Zoom Out Complete: \(String(format: "%.2f", complete))s")
                    }
                }
                
                if let sets = clip.detectedSets {
                    print("    • Detected Exercise Sets: \(sets.count)")
                    for (setIndex, set) in sets.enumerated() {
                        print("      Set \(setIndex + 1): \(set.reps) reps (\(String(format: "%.2f", set.startTime))s → \(String(format: "%.2f", set.endTime))s)")
                    }
                }
            }

            // Create and log AIVideoClipStates
            let aiClipStates = clips.map { clip in
                // Convert ZoomConfig to dictionary format
                let zoomConfigDict: [String: Double]?
                if let config = clip.zoomConfig {
                    zoomConfigDict = [
                        "startZoomIn": config.startZoomIn,
                        "zoomInComplete": config.zoomInComplete ?? -1,
                        "startZoomOut": config.startZoomOut ?? -1,
                        "zoomOutComplete": config.zoomOutComplete ?? -1,
                    ].filter { $0.value != -1 }
                } else {
                    zoomConfigDict = nil
                }

                return AIVideoClipState(
                    id: clip.id,
                    startTime: clip.startTime,
                    endTime: clip.endTime,
                    zoomConfig: zoomConfigDict,
                    detectedSets: clip.detectedSets?.map { set in
                        AIDetectedSet(
                            reps: set.reps,
                            startTime: set.startTime,
                            endTime: set.endTime,
                            keyJoint: set.keyJoint
                        )
                    }
                )
            }

            print("\n🤖 AI State Representation")
            print("-----------------------")
            for (index, state) in aiClipStates.enumerated() {
                print("\n  Clip \(index) State:")
                print("    • ID: \(state.id)")
                print("    • Timeline: \(String(format: "%.2f", state.startTime))s → \(String(format: "%.2f", state.endTime))s")
                if let zoom = state.zoomConfig {
                    print("    • Zoom Config:", zoom)
                }
                if let sets = state.detectedSets {
                    print("    • Exercise Sets: \(sets.count)")
                    for (setIndex, set) in sets.enumerated() {
                        print("      Set \(setIndex + 1): \(set.reps) reps at \(set.keyJoint) (\(String(format: "%.2f", set.startTime))s → \(String(format: "%.2f", set.endTime))s)")
                    }
                }
            }

            // Log editor state
            let currentState = AIEditorState(
                clips: aiClipStates,
                selectedClipIndex: selectedClipIndex
            )

            print("\n🎯 Editor State")
            print("-------------")
            print("  • Total Clips: \(currentState.clips.count)")
            print("  • Selected Clip Index: \(currentState.selectedClipIndex?.description ?? "none")")
            print("  • Total Duration: \(String(format: "%.2f", totalDuration))s")

            // Log edit history
            let aiEditHistory = editHistory.map { entry in
                // Convert EditAction to AIEditAction
                let aiAction: AIEditAction
                switch entry.action {
                case let .addClip(clipId):
                    aiAction = AIEditAction(type: "addClip", clipId: String(clipId), index: nil, from: nil, to: nil, time: nil, startTime: nil, endTime: nil, volume: nil, config: nil)
                case let .deleteClip(index):
                    aiAction = AIEditAction(type: "deleteClip", clipId: nil, index: index, from: nil, to: nil, time: nil, startTime: nil, endTime: nil, volume: nil, config: nil)
                case let .moveClip(from, to):
                    aiAction = AIEditAction(type: "moveClip", clipId: nil, index: nil, from: from, to: to, time: nil, startTime: nil, endTime: nil, volume: nil, config: nil)
                case let .swapClips(index):
                    aiAction = AIEditAction(type: "swapClips", clipId: nil, index: index, from: nil, to: nil, time: nil, startTime: nil, endTime: nil, volume: nil, config: nil)
                case let .splitClip(time):
                    aiAction = AIEditAction(type: "splitClip", clipId: nil, index: nil, from: nil, to: nil, time: time, startTime: nil, endTime: nil, volume: nil, config: nil)
                case let .trimClip(clipId, startTime, endTime):
                    aiAction = AIEditAction(type: "trimClip", clipId: String(clipId), index: nil, from: nil, to: nil, time: nil, startTime: startTime, endTime: endTime, volume: nil, config: nil)
                case let .updateVolume(clipId, volume):
                    aiAction = AIEditAction(type: "updateVolume", clipId: String(clipId), index: nil, from: nil, to: nil, time: nil, startTime: nil, endTime: nil, volume: volume, config: nil)
                case let .updateZoom(clipId, config):
                    let configDict = config.map { conf in
                        [
                            "startZoomIn": conf.startZoomIn,
                            "zoomInComplete": conf.zoomInComplete,
                            "startZoomOut": conf.startZoomOut,
                            "zoomOutComplete": conf.zoomOutComplete,
                        ].compactMapValues { $0 }
                    }
                    aiAction = AIEditAction(type: "updateZoom", clipId: String(clipId), index: nil, from: nil, to: nil, time: nil, startTime: nil, endTime: nil, volume: nil, config: configDict)
                }

                return AIEditHistoryEntry(
                    id: entry.id.uuidString,
                    title: entry.title,
                    timestamp: entry.timestamp.timeIntervalSince1970 * 1000,
                    action: aiAction,
                    isApplied: true
                )
            }

            print("\n📜 Edit History")
            print("-------------")
            for (index, entry) in aiEditHistory.enumerated() {
                print("\n  Edit \(index + 1):")
                print("    • ID: \(entry.id)")
                print("    • Action: \(entry.action.type)")
                print("    • Title: \(entry.title)")
                print("    • Timestamp: \(Date(timeIntervalSince1970: entry.timestamp / 1000))")
                
                // Print action-specific details
                switch entry.action.type {
                    case "addClip":
                        if let clipId = entry.action.clipId {
                            print("    • Added Clip ID: \(clipId)")
                        }
                    case "deleteClip":
                        if let index = entry.action.index {
                            print("    • Deleted at Index: \(index)")
                        }
                    case "moveClip":
                        if let from = entry.action.from, let to = entry.action.to {
                            print("    • Moved from \(from) to \(to)")
                        }
                    case "splitClip":
                        if let time = entry.action.time {
                            print("    • Split at: \(String(format: "%.2f", time))s")
                        }
                    case "trimClip":
                        if let start = entry.action.startTime, let end = entry.action.endTime {
                            print("    • Trimmed: \(String(format: "%.2f", start))s → \(String(format: "%.2f", end))s")
                        }
                    case "updateVolume":
                        if let volume = entry.action.volume {
                            print("    • Volume set to: \(String(format: "%.2f", volume))")
                        }
                    case "updateZoom":
                        if let config = entry.action.config {
                            print("    • Zoom config updated: \(config)")
                        }
                    default:
                        break
                }
            }

            // Create final request
            let request = AIEditSuggestionRequest(
                prompt: prompt,
                currentState: currentState,
                editHistory: aiEditHistory
            )

            print("\n📦 Request Summary")
            print("----------------")
            print("  • Prompt: \(prompt)")
            print("  • Total Clips: \(currentState.clips.count)")
            print("  • History Entries: \(aiEditHistory.count)")

            // Configure encoder
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.keyEncodingStrategy = .useDefaultKeys

            // Encode and log the final JSON
            print("\n🔍 Final JSON Request")
            print("------------------")
            let jsonData = try encoder.encode(request)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }

            print("\n🚀 Sending request to Cloud Function...")

            // Convert to dictionary before sending to Firebase
            let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as! [String: Any]

            // Inside requestAIEditSuggestion, before calling the Cloud Function:
            print("\n🔍 Dictionary being sent to Firebase:")
            if let prettyPrintedJson = try? JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted),
               let jsonString = String(data: prettyPrintedJson, encoding: .utf8)
            {
                print(jsonString)
            }

            // Call the Cloud Function with the dictionary
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("suggestEdits").call(dictionary)

            print("\n✅ Received response from Cloud Function")

            // Parse the response
            guard let data = result.data as? [String: Any],
                  let suggestions = data["suggestions"] as? [[String: Any]],
                  let suggestion = suggestions.first
            else {
                print("❌ Error: Invalid response format")
                return
            }

            // Log the suggestion
            print("\n💡 AI Suggestion:")
            print("Action:", suggestion["action"] ?? "No action")
            print("Explanation:", suggestion["explanation"] ?? "No explanation")
            print("Confidence:", suggestion["confidence"] ?? "No confidence score")

            // Apply the suggestion with the original prompt
            do {
                try await applyAISuggestion(suggestion, userPrompt: prompt)
                print("✅ Successfully applied AI suggestion")
            } catch {
                print("❌ Error applying AI suggestion:", error.localizedDescription)
            }

        } catch {
            print("\n❌ Error requesting AI suggestion:")
            print("Error type: \(type(of: error))")
            print("Error description: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error user info: \(nsError.userInfo)")
            }
        }
    }

    // Apply AI suggestion
    private func applyAISuggestion(_ suggestion: [String: Any], userPrompt: String) async throws {
        guard let action = suggestion["action"] as? [String: Any],
              let actionType = action["type"] as? String
        else {
            throw NSError(domain: "AIEditError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid action format"])
        }

        print("Applying AI suggestion of type: \(actionType)")

        switch actionType {
        case "deleteClip":
            if let index = action["index"] as? Int {
                await MainActor.run {
                    // Store current state before modification
                    let newState = EditorState(
                        clips: clips,
                        selectedClipIndex: selectedClipIndex
                    )

                    // Delete the clip
                    deleteClip(at: index)

                    // Replace the automatically created history entry with one that includes the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "moveClip":
            if let from = action["from"] as? Int,
               let to = action["to"] as? Int
            {
                await MainActor.run {
                    moveClip(from: IndexSet(integer: from), to: to)
                    // Update the last history entry with the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "swapClips":
            if let index = action["index"] as? Int {
                await MainActor.run {
                    swapClips(at: index)
                    // Update the last history entry with the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "splitClip":
            if let time = action["time"] as? Double {
                await splitClip(at: time)
                // Update the last history entry with the prompt
                await MainActor.run {
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "trimClip":
            if let clipIdStr = action["clipId"] as? String,
               let clipId = Int(clipIdStr),
               let startTime = action["startTime"] as? Double,
               let endTime = action["endTime"] as? Double,
               let index = clips.firstIndex(where: { $0.id == clipId })
            {
                let clip = clips[index]

                // Convert asset-relative times to composition times
                let compositionStartTime = clip.startTime + (startTime - clip.assetStartTime)
                let compositionEndTime = clip.startTime + (endTime - clip.assetStartTime)

                await MainActor.run {
                    selectedClipIndex = index
                    updateClipTrim(startTime: compositionStartTime, endTime: compositionEndTime)
                    // Update the last history entry with the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "updateVolume":
            if let clipIdStr = action["clipId"] as? String,
               let clipId = Int(clipIdStr),
               let volume = action["volume"] as? Double,
               let index = clips.firstIndex(where: { $0.id == clipId })
            {
                await MainActor.run {
                    selectedClipIndex = index
                    updateClipVolume(volume)
                    // Update the last history entry with the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        case "updateZoom":
            if let clipIdStr = action["clipId"] as? String,
               let clipId = Int(clipIdStr),
               let index = clips.firstIndex(where: { $0.id == clipId })
            {
                let config: ZoomConfig?
                if let configDict = action["config"] as? [String: Double] {
                    config = ZoomConfig(
                        startZoomIn: configDict["startZoomIn"] ?? 0,
                        zoomInComplete: configDict["zoomInComplete"],
                        startZoomOut: configDict["startZoomOut"],
                        zoomOutComplete: configDict["zoomOutComplete"]
                    )
                } else {
                    config = nil
                }
                await MainActor.run {
                    updateZoomConfig(at: index, config: config)
                    // Update the last history entry with the prompt
                    if let lastEntry = editHistory.last {
                        let newEntry = EditHistoryEntry(
                            title: lastEntry.title,
                            timestamp: lastEntry.timestamp,
                            state: lastEntry.state,
                            action: lastEntry.action,
                            prompt: userPrompt
                        )
                        editHistory[editHistory.count - 1] = newEntry
                    }
                }
            }

        default:
            throw NSError(domain: "AIEditError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported action type: \(actionType)"])
        }
    }
}

// Helper extension to safely access array elements
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// Extension for transform interpolation
extension CGAffineTransform {
    func interpolating(to target: CGAffineTransform, amount: Double) -> CGAffineTransform {
        let clampedAmount = max(0, min(1, amount))
        return CGAffineTransform(
            a: a + (target.a - a) * CGFloat(clampedAmount),
            b: b + (target.b - b) * CGFloat(clampedAmount),
            c: c + (target.c - c) * CGFloat(clampedAmount),
            d: d + (target.d - d) * CGFloat(clampedAmount),
            tx: tx + (target.tx - tx) * CGFloat(clampedAmount),
            ty: ty + (target.ty - ty) * CGFloat(clampedAmount)
        )
    }
}

// Supporting types for AI suggestions
struct AIDetectedSet: Codable {
    let reps: Int
    let startTime: Double
    let endTime: Double
    let keyJoint: String
}

struct AIVideoClipState: Codable {
    let id: Int
    let startTime: Double
    let endTime: Double
    let zoomConfig: [String: Double]?
    let detectedSets: [AIDetectedSet]?
}

struct AIEditSuggestionRequest: Codable {
    let prompt: String
    let currentState: AIEditorState
    let editHistory: [AIEditHistoryEntry]
}

struct AIEditorState: Codable {
    let clips: [AIVideoClipState]
    let selectedClipIndex: Int?
}

struct AIEditHistoryEntry: Codable {
    let id: String
    let title: String
    let timestamp: TimeInterval
    let action: AIEditAction
    let isApplied: Bool

    init(id: String, title: String, timestamp: TimeInterval, action: AIEditAction, isApplied: Bool) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.action = action
        self.isApplied = isApplied
    }
}

// Match the TypeScript schema exactly
struct AIEditAction: Codable {
    let type: String
    let clipId: String?
    let index: Int?
    let from: Int?
    let to: Int?
    let time: Double?
    let startTime: Double?
    let endTime: Double?
    let volume: Double?
    let config: [String: Double]?

    private enum CodingKeys: String, CodingKey {
        case type
        case clipId
        case index
        case from
        case to
        case time
        case startTime
        case endTime
        case volume
        case config
    }
}
