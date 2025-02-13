import AVFoundation
import Foundation
import Vision

class SetDetectionService {

// MARK: - Data Structures


// A helper structure representing one rep cycle.
private struct RepCycle {
    let startTime: Double
    let peakTime: Double
    let endTime: Double
}

// MARK: - Main Function

func detectSets(from poseResults: [PoseResult]) -> [DetectedExerciseSet] {
    // List of candidate keypoints that are likely to be moving for most exercises.
    let candidateKeypointTypes: [KeypointType] = [
        .leftWrist, .rightWrist,
        .leftElbow, .rightElbow,
        .leftAnkle, .rightAnkle,
        .leftKnee, .rightKnee
    ]
    
    // Build time series for each candidate keypoint.
    var candidateTimeSeries: [KeypointType: [(timestamp: Double, point: CGPoint)]] = [:]
    candidateKeypointTypes.forEach { candidateTimeSeries[$0] = [] }
    
    let confidenceThreshold: Float = 0.5
    for result in poseResults {
        for keypoint in result.keypoints {
            if candidateKeypointTypes.contains(keypoint.type) && keypoint.confidence >= confidenceThreshold {
                candidateTimeSeries[keypoint.type]?.append((timestamp: result.timestamp, point: keypoint.position))
            }
        }
    }
    
    // Choose the candidate with the largest overall movement (variance).
    var bestCandidate: KeypointType?
    var bestVariance: CGFloat = 0
    var bestTimeSeries: [(timestamp: Double, point: CGPoint)] = []
    
    for (type, series) in candidateTimeSeries {
        guard series.count >= 2 else { continue }
        let points = series.map { $0.point }
        let meanPoint = CGPoint(
            x: points.reduce(0, { $0 + $1.x }) / CGFloat(points.count),
            y: points.reduce(0, { $0 + $1.y }) / CGFloat(points.count)
        )
        let variance = points.reduce(0) { $0 + pow($1.x - meanPoint.x, 2) + pow($1.y - meanPoint.y, 2) } / CGFloat(points.count)
        if variance > bestVariance {
            bestVariance = variance
            bestCandidate = type
            bestTimeSeries = series
        }
    }
    
    // If no candidate data was found, return an empty set.
    guard bestCandidate != nil, bestTimeSeries.count >= 2 else { return [] }
    
    // Sort the selected time series by timestamp.
    bestTimeSeries.sort { $0.timestamp < $1.timestamp }
    
    // Compute the primary (principal) axis of movement.
    let points = bestTimeSeries.map { $0.point }
    let meanPoint = CGPoint(
        x: points.reduce(0, { $0 + $1.x }) / CGFloat(points.count),
        y: points.reduce(0, { $0 + $1.y }) / CGFloat(points.count)
    )
    
    var covXX: CGFloat = 0, covXY: CGFloat = 0, covYY: CGFloat = 0
    for p in points {
        let dx = p.x - meanPoint.x
        let dy = p.y - meanPoint.y
        covXX += dx * dx
        covXY += dx * dy
        covYY += dy * dy
    }
    let n = CGFloat(points.count)
    covXX /= n
    covXY /= n
    covYY /= n
    
    // The angle of the principal component.
    let angle = 0.5 * atan2(2 * covXY, covXX - covYY)
    let principalAxis = CGPoint(x: cos(angle), y: sin(angle))
    
    // Project each point onto the principal axis.
    var projectedSignal: [(timestamp: Double, value: CGFloat)] = []
    for (timestamp, point) in bestTimeSeries {
        let dx = point.x - meanPoint.x
        let dy = point.y - meanPoint.y
        let projection = dx * principalAxis.x + dy * principalAxis.y
        projectedSignal.append((timestamp: timestamp, value: projection))
    }
    
    // Smooth the projected signal to reduce noise.
    let smoothedSignal = movingAverage(signal: projectedSignal, windowSize: 5)
    
    // Detect rep cycles in the smoothed signal.
    let repCycles = detectReps(from: smoothedSignal)
    
    // Group cycles into sets based on a gap threshold.
    let setGapThreshold: Double = 2.0  // seconds
    var detectedSets: [DetectedExerciseSet] = []
    if !repCycles.isEmpty {
        var currentSetStart = repCycles.first!.startTime
        var currentSetEnd = repCycles.first!.endTime
        var repCount = 1
        for cycle in repCycles.dropFirst() {
            let gap = cycle.startTime - currentSetEnd
            if gap > setGapThreshold {
                detectedSets.append(DetectedExerciseSet(reps: repCount, startTime: currentSetStart, endTime: currentSetEnd,  keyJoint: bestCandidate!.rawValue))
                currentSetStart = cycle.startTime
                repCount = 1
            } else {
                repCount += 1
            }
            currentSetEnd = cycle.endTime
        }
        detectedSets.append(DetectedExerciseSet(reps: repCount, startTime: currentSetStart, endTime: currentSetEnd, keyJoint: bestCandidate!.rawValue))
    }
    
    return detectedSets
}

// MARK: - Helper Functions

/// Applies a simple moving average to smooth the signal.
private func movingAverage(signal: [(timestamp: Double, value: CGFloat)], windowSize: Int) -> [(timestamp: Double, value: CGFloat)] {
    guard windowSize > 0, !signal.isEmpty else { return signal }
    var smoothed: [(timestamp: Double, value: CGFloat)] = []
    let halfWindow = windowSize / 2
    for i in 0..<signal.count {
        let start = max(0, i - halfWindow)
        let end = min(signal.count - 1, i + halfWindow)
        let window = signal[start...end]
        let averageValue = window.map { $0.value }.reduce(0, +) / CGFloat(window.count)
        smoothed.append((timestamp: signal[i].timestamp, value: averageValue))
    }
    return smoothed
}

/// Detects rep cycles from the smoothed 1D signal by finding local minima-to-minima cycles that contain a peak.
private func detectReps(from signal: [(timestamp: Double, value: CGFloat)]) -> [RepCycle] {
    guard signal.count >= 3 else { return [] }
    
    var minimaIndices: [Int] = []
    var maximaIndices: [Int] = []
    
    // Identify local minima and maxima.
    for i in 1..<signal.count - 1 {
        if signal[i].value < signal[i - 1].value && signal[i].value < signal[i + 1].value {
            minimaIndices.append(i)
        }
        if signal[i].value > signal[i - 1].value && signal[i].value > signal[i + 1].value {
            maximaIndices.append(i)
        }
    }
    
    // Form cycles from one minimum to the next with a peak in between.
    var cycles: [RepCycle] = []
    // Compute the global range to later require a minimum amplitude change.
    let globalMax = signal.map { $0.value }.max() ?? 0
    let globalMin = signal.map { $0.value }.min() ?? 0
    let globalRange = globalMax - globalMin
    
    for i in 0..<minimaIndices.count - 1 {
        let startIndex = minimaIndices[i]
        let endIndex = minimaIndices[i + 1]
        // Look for a maximum between the two minima.
        let candidateMaxima = maximaIndices.filter { $0 > startIndex && $0 < endIndex }
        guard let peakIndex = candidateMaxima.max(by: { signal[$0].value < signal[$1].value }) else { continue }
        
        // Ensure that the movement is significant.
        let amplitude = signal[peakIndex].value - min(signal[startIndex].value, signal[endIndex].value)
        if amplitude >= 0.1 * globalRange {
            let cycle = RepCycle(startTime: signal[startIndex].timestamp,
                                 peakTime: signal[peakIndex].timestamp,
                                 endTime: signal[endIndex].timestamp)
            print("✅ Rep cycle detected: \(cycle)")
            print("🔍 Peak time: \(cycle.peakTime)")
            print("🔍 Start time: \(cycle.startTime)")
            print("🔍 End time: \(cycle.endTime)")
            cycles.append(cycle)
        }
    }
    
    return cycles
}
}

// MARK: - KeypointType Extensions
extension KeypointType {
    var bodyPart: String {
        switch self {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
            return "Head"
        case .leftShoulder, .rightShoulder:
            return "Shoulder"
        case .leftElbow, .rightElbow:
            return "Elbow"
        case .leftWrist, .rightWrist:
            return "Wrist"
        case .leftHip, .rightHip:
            return "Hip"
        case .leftKnee, .rightKnee:
            return "Knee"
        case .leftAnkle, .rightAnkle:
            return "Ankle"
        }
    }
}