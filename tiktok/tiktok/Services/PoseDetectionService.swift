import AVFoundation
import Vision

actor PoseDetectionService {
    private var activeDetections: [UUID: Task<[PoseResult], Error>] = [:]

    func detectPoses(for clip: VideoClip) async throws -> [PoseResult] {
        // Cancel any existing detection for this clip
        activeDetections[clip.id]?.cancel()

        let task = Task {
            var results: [PoseResult] = []
            let asset = clip.asset

            // Configure request
            let request = VNDetectHumanBodyPoseRequest()

            // Generate frames at 10fps
            let duration = try await asset.load(.duration)
            let frameCount = Int(duration.seconds * 10)
            let interval = duration.seconds / Double(frameCount)

            // Process frames
            for frameIndex in 0 ..< frameCount {
                try Task.checkCancellation()

                let time = CMTime(seconds: Double(frameIndex) * interval, preferredTimescale: 600)
                let image = try await generateFrame(from: asset, at: time)

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                try handler.perform([request])

                if let observation = request.results?.first {
                    let keypoints = try processObservation(observation, timestamp: time.seconds)
                    results.append(PoseResult(timestamp: time.seconds, keypoints: keypoints))
                }
            }

            return results
        }

        activeDetections[clip.id] = task
        return try await task.value
    }

    private func generateFrame(from asset: AVAsset, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        let cgImage = try await generator.image(at: time).image
        return cgImage
    }

    private func processObservation(_ observation: VNHumanBodyPoseObservation, timestamp _: Double) throws -> [PoseKeypoint] {
        var keypoints: [PoseKeypoint] = []

        // Map Vision keypoints to our model
        let recognizedPoints = try observation.recognizedPoints(.all)

        for (visionKey, point) in recognizedPoints {
            guard let keypointType = mapVisionKeypoint(visionKey) else { continue }

            let position = CGPoint(x: point.location.x, y: 1 - point.location.y) // Flip Y coordinate
            keypoints.append(PoseKeypoint(
                position: position,
                confidence: point.confidence,
                type: keypointType
            ))
        }

        return keypoints
    }

    private func mapVisionKeypoint(_ key: VNHumanBodyPoseObservation.JointName) -> KeypointType? {
        switch key {
        case .nose: return .nose
        case .leftEye: return .leftEye
        case .rightEye: return .rightEye
        case .leftEar: return .leftEar
        case .rightEar: return .rightEar
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        default: return nil
        }
    }

    func cancelDetection(for clipId: UUID) {
        activeDetections[clipId]?.cancel()
        activeDetections[clipId] = nil
    }
}
