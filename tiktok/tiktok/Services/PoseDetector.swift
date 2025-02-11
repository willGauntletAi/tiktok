import Foundation
import Vision

protocol PoseDetector {
    func detectPose(in image: CGImage) async throws -> VNHumanBodyPoseObservation?
}

class MLKitPoseDetector: PoseDetector {
    func detectPose(in image: CGImage) async throws -> VNHumanBodyPoseObservation? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results?.first
    }
}
