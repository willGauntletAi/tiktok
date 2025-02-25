import AVFoundation
import UIKit

struct VideoClip: Identifiable {
    let id: Int
    let asset: AVAsset
    var startTime: Double // Position in composition
    var endTime: Double // Position in composition
    var thumbnail: UIImage?
    var volume: Double
    var assetStartTime: Double // Original time in asset
    var assetDuration: Double // Original duration in asset
    var zoomConfig: ZoomConfig?
    var poseDetectionStatus: PoseDetectionStatus = .pending
    var poseResults: [PoseResult]?
    var detectedSets: [DetectedExerciseSet]?

    private static let idGenerator = AtomicIntGenerator()

    init(asset: AVAsset, startTime: Double = 0, endTime: Double? = nil, thumbnail: UIImage? = nil, assetStartTime: Double = 0, assetDuration: Double? = nil) {
        id = Self.idGenerator.next()
        self.asset = asset
        self.startTime = startTime
        self.endTime = endTime ?? 0 // Will be set after loading duration
        self.thumbnail = thumbnail
        volume = 1.0
        self.assetStartTime = assetStartTime
        if let duration = assetDuration {
            self.assetDuration = duration
        } else {
            self.assetDuration = (endTime ?? 0) - startTime
        }
        zoomConfig = nil
        poseResults = nil
    }
}

// Thread-safe ID generator
final class AtomicIntGenerator {
    private var current = 0
    private let queue = DispatchQueue(label: "com.tiktok.idgenerator")

    func next() -> Int {
        queue.sync {
            current += 1
            return current
        }
    }
}

struct ZoomConfig: Codable {
    var startZoomIn: Double // Required - when to start zooming in
    var zoomInComplete: Double? // Optional - when zoom in completes
    var startZoomOut: Double? // Optional - when to start zooming out
    var zoomOutComplete: Double? // Optional - when zoom out completes
    var focusedJoint: KeypointType? // Optional - the joint to focus the zoom on

    init(startZoomIn: Double, zoomInComplete: Double? = nil, startZoomOut: Double? = nil, zoomOutComplete: Double? = nil, focusedJoint: KeypointType? = nil) {
        self.startZoomIn = startZoomIn
        self.zoomInComplete = zoomInComplete
        self.startZoomOut = startZoomOut
        self.zoomOutComplete = zoomOutComplete
        self.focusedJoint = focusedJoint
    }
}

enum PoseDetectionStatus: Equatable {
    case pending
    case inProgress
    case completed
    case failed(Error)

    static func == (lhs: PoseDetectionStatus, rhs: PoseDetectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.inProgress, .inProgress),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            return true // Note: We consider all errors equal for Equatable conformance
        default:
            return false
        }
    }
}

struct PoseResult: Codable {
    let timestamp: Double
    let keypoints: [PoseKeypoint]
}

struct PoseKeypoint: Codable {
    let position: CGPoint
    let confidence: Float
    let type: KeypointType
}

enum KeypointType: String, Codable, CaseIterable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle

    var displayName: String {
        switch self {
        case .nose: return "Nose"
        case .leftEye: return "Left Eye"
        case .rightEye: return "Right Eye"
        case .leftEar: return "Left Ear"
        case .rightEar: return "Right Ear"
        case .leftShoulder: return "Left Shoulder"
        case .rightShoulder: return "Right Shoulder"
        case .leftElbow: return "Left Elbow"
        case .rightElbow: return "Right Elbow"
        case .leftWrist: return "Left Wrist"
        case .rightWrist: return "Right Wrist"
        case .leftHip: return "Left Hip"
        case .rightHip: return "Right Hip"
        case .leftKnee: return "Left Knee"
        case .rightKnee: return "Right Knee"
        case .leftAnkle: return "Left Ankle"
        case .rightAnkle: return "Right Ankle"
        }
    }
}
