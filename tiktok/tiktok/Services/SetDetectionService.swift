import Foundation
import AVFoundation
import Vision

class SetDetectionService {
    private var videoAsset: AVAsset?
    private var poseObservations: [VNHumanBodyPoseObservation] = []
    private let analysisQueue = DispatchQueue(label: "com.app.setdetection", qos: .userInitiated)
    
    private struct JointPosition {
        let point: CGPoint
        let confidence: Float
        
        static let minimumConfidence: Float = 0.3
    }
    
    private struct JointPositions {
        var rightWrist: JointPosition?
        var leftWrist: JointPosition?
        var rightElbow: JointPosition?
        var leftElbow: JointPosition?
        var rightHip: JointPosition?
        var leftHip: JointPosition?
        var rightAnkle: JointPosition?
        var leftAnkle: JointPosition?
        
        init(from observation: VNHumanBodyPoseObservation) {
            // Try to get each joint, but don't require all of them
            if let point = try? observation.recognizedPoint(.rightWrist),
               point.confidence > JointPosition.minimumConfidence {
                rightWrist = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.leftWrist),
               point.confidence > JointPosition.minimumConfidence {
                leftWrist = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.rightElbow),
               point.confidence > JointPosition.minimumConfidence {
                rightElbow = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.leftElbow),
               point.confidence > JointPosition.minimumConfidence {
                leftElbow = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.rightHip),
               point.confidence > JointPosition.minimumConfidence {
                rightHip = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.leftHip),
               point.confidence > JointPosition.minimumConfidence {
                leftHip = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.rightAnkle),
               point.confidence > JointPosition.minimumConfidence {
                rightAnkle = JointPosition(point: point.location, confidence: point.confidence)
            }
            
            if let point = try? observation.recognizedPoint(.leftAnkle),
               point.confidence > JointPosition.minimumConfidence {
                leftAnkle = JointPosition(point: point.location, confidence: point.confidence)
            }
        }
        
        // Get average Y position of visible joints in a group
        func getAverageY(joints: [JointPosition?]) -> Double? {
            let visibleJoints = joints.compactMap { $0 }
            guard !visibleJoints.isEmpty else { return nil }
            
            return Double(visibleJoints.reduce(0) { $0 + $1.point.y }) / Double(visibleJoints.count)
        }
    }
    
    private struct FrameAnalysis {
        let positions: JointPositions
        var upperBodyMovement: MovementDirection?
        var lowerBodyMovement: MovementDirection?
        
        init(positions: JointPositions, previous: JointPositions?) {
            self.positions = positions
            
            // Get upper body movement if we have enough visible joints
            if let currentUpperY = positions.getAverageY(joints: [
                positions.rightWrist, positions.leftWrist,
                positions.rightElbow, positions.leftElbow
            ]),
               let previousUpperY = previous?.getAverageY(joints: [
                positions.rightWrist, positions.leftWrist,
                positions.rightElbow, positions.leftElbow
               ]) {
                self.upperBodyMovement = currentUpperY > previousUpperY ? .up : .down
            }
            
            // Get lower body movement if we have enough visible joints
            if let currentLowerY = positions.getAverageY(joints: [
                positions.rightHip, positions.leftHip,
                positions.rightAnkle, positions.leftAnkle
            ]),
               let previousLowerY = previous?.getAverageY(joints: [
                positions.rightHip, positions.leftHip,
                positions.rightAnkle, positions.leftAnkle
               ]) {
                self.lowerBodyMovement = currentLowerY > previousLowerY ? .up : .down
            }
        }
    }
    
    private class RepState {
        enum Phase {
            case initial      // Starting position
            case moving      // Moving away from start
            case returning   // Moving back to start
        }
        
        var phase: Phase = .initial
        var startingUpperDirection: MovementDirection?
        var startingLowerDirection: MovementDirection?
        var framesSinceLastPhaseChange = 0
        
        func update(with analysis: FrameAnalysis, previous: FrameAnalysis?) -> Bool {
            framesSinceLastPhaseChange += 1
            
            guard let previous = previous else { return false }
            
            switch phase {
            case .initial:
                // Detect initial movement direction
                if let upperMove = analysis.upperBodyMovement,
                   upperMove != previous.upperBodyMovement {
                    startingUpperDirection = upperMove
                    phase = .moving
                    framesSinceLastPhaseChange = 0
                } else if let lowerMove = analysis.lowerBodyMovement,
                          lowerMove != previous.lowerBodyMovement {
                    startingLowerDirection = lowerMove
                    phase = .moving
                    framesSinceLastPhaseChange = 0
                }
                return false
                
            case .moving:
                // Look for reversal of direction
                if (startingUpperDirection != nil && 
                    analysis.upperBodyMovement == startingUpperDirection?.opposite()) ||
                   (startingLowerDirection != nil && 
                    analysis.lowerBodyMovement == startingLowerDirection?.opposite()) {
                    phase = .returning
                    framesSinceLastPhaseChange = 0
                }
                return false
                
            case .returning:
                // Look for return to original direction (completing the rep)
                if (startingUpperDirection != nil && 
                    analysis.upperBodyMovement == startingUpperDirection) ||
                   (startingLowerDirection != nil && 
                    analysis.lowerBodyMovement == startingLowerDirection) {
                    // Reset for next rep
                    phase = .initial
                    startingUpperDirection = nil
                    startingLowerDirection = nil
                    framesSinceLastPhaseChange = 0
                    return true // Completed rep
                }
                return false
            }
        }
        
        func shouldResetDueToInactivity() -> Bool {
            // Reset if no phase change for 30 frames (1 second at 30fps)
            return framesSinceLastPhaseChange > 30
        }
    }
    
    /// Analyzes a video clip to detect exercise sets
    /// - Parameters:
    ///   - videoURL: URL of the video to analyze
    /// - Returns: Array of detected exercise sets
    /// - Throws: SetDetectionError if analysis fails
    func detectSets(from videoURL: URL) async throws -> ExerciseSets {
        let asset = AVURLAsset(url: videoURL)
        
        self.videoAsset = asset
        self.poseObservations = []
        
        let observations = try await analyzeVideoFrames(asset: asset)
        return try await processPoseObservations(observations)
    }
    
    private func analyzeVideoFrames(asset: AVAsset) async throws -> [VNHumanBodyPoseObservation] {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SetDetectionError.invalidVideoAsset
        }
        
        // Create video sample buffer request
        let request = VNDetectHumanBodyPoseRequest()
        var observations: [VNHumanBodyPoseObservation] = []
        
        // Setup video analysis
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        let frameRate: Double = 30 // We'll analyze 30 frames per second
        let totalFrames = Int(durationSeconds * frameRate)
        
        for frameIndex in 0..<totalFrames {
            let time = CMTime(seconds: Double(frameIndex) / frameRate, preferredTimescale: 600)
            
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            
            if let observation = request.results?.first {
                observations.append(observation)
            }
        }
        
        return observations
    }
    
    private func processPoseObservations(_ observations: [VNHumanBodyPoseObservation]) async throws -> ExerciseSets {
        var sets: [ExerciseSet] = []
        var currentSetStartIndex: Int?
        var repCount = 0
        var lastAnalysis: FrameAnalysis?
        var frameAnalyses: [FrameAnalysis] = []
        let repState = RepState()
        
        // First, convert observations to frame analyses
        for (index, observation) in observations.enumerated() {
            let positions = JointPositions(from: observation)
            let previousPositions = index > 0 ? JointPositions(from: observations[index - 1]) : nil
            let analysis = FrameAnalysis(positions: positions, previous: previousPositions)
            frameAnalyses.append(analysis)
            
            // Detect rep based on movement cycle
            if repState.update(with: analysis, previous: lastAnalysis) {
                repCount += 1
                
                // Start new set if this is the first rep
                if currentSetStartIndex == nil {
                    currentSetStartIndex = index
                }
            }
            
            // Check for inactivity or long pause
            if repState.shouldResetDueToInactivity() {
                // End current set if we have one
                if let startIndex = currentSetStartIndex, repCount > 0 {
                    let startTime = Double(startIndex) / 30.0
                    let endTime = Double(index) / 30.0
                    
                    sets.append(ExerciseSet(
                        reps: repCount,
                        startTime: startTime,
                        endTime: endTime
                    ))
                    
                    // Reset for next set
                    currentSetStartIndex = nil
                    repCount = 0
                }
                
                // Reset rep detection state
                repState.phase = .initial
                repState.startingUpperDirection = nil
                repState.startingLowerDirection = nil
                repState.framesSinceLastPhaseChange = 0
            }
            
            lastAnalysis = analysis
        }
        
        // Add final set if in progress
        if let startIndex = currentSetStartIndex, repCount > 0 {
            let startTime = Double(startIndex) / 30.0
            let endTime = Double(observations.count - 1) / 30.0
            
            sets.append(ExerciseSet(
                reps: repCount,
                startTime: startTime,
                endTime: endTime
            ))
        }
        
        return sets
    }
}

enum SetDetectionError: Error {
    case invalidVideoAsset
    case analysisFailure
}

private enum MovementDirection {
    case up
    case down
    
    func opposite() -> MovementDirection {
        return self == .up ? .down : .up
    }
} 