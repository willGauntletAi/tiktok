import AVFoundation
import Foundation
import Vision

// MARK: - Data Structures

// A helper structure representing one rep cycle.
// Now includes an amplitude property computed from the 1D signal.
private struct RepCycle {
    let startTime: Double
    let peakTime: Double
    let endTime: Double
    let amplitude: CGFloat
}

// To store the candidate joint’s rep cycle data along with its smoothed signal.
private struct JointCycleData {
    let keypointType: KeypointType
    let cycles: [RepCycle]
    let smoothedSignal: [(timestamp: Double, value: CGFloat)]
}

// MARK: - Main Function

class SetDetectionService {
    func detectSets(from poseResults: [PoseResult]) -> [DetectedExerciseSet] {
        // List of candidate keypoints (joints) likely to be moving.
        let candidateKeypointTypes: [KeypointType] = [
            .leftWrist, .rightWrist,
            .leftElbow, .rightElbow,
            .leftAnkle, .rightAnkle,
            .leftKnee, .rightKnee,
        ]

        // Build time series for each candidate joint.
        var candidateTimeSeries: [KeypointType: [(timestamp: Double, point: CGPoint)]] = [:]
        candidateKeypointTypes.forEach { candidateTimeSeries[$0] = [] }

        let confidenceThreshold: Float = 0.5
        for result in poseResults {
            for keypoint in result.keypoints {
                if candidateKeypointTypes.contains(keypoint.type),
                   keypoint.confidence >= confidenceThreshold
                {
                    candidateTimeSeries[keypoint.type]?.append((timestamp: result.timestamp, point: keypoint.position))
                }
            }
        }

        // For each candidate, project its 2D points onto its principal axis,
        // smooth the 1D signal and detect rep cycles.
        var jointCycleDataList: [JointCycleData] = []

        for (jointType, series) in candidateTimeSeries {
            print("🔍 Type: \(jointType), count: \(series.count)")
            guard series.count >= 2 else { continue }

            // Sort by timestamp.
            let sortedSeries = series.sorted { $0.timestamp < $1.timestamp }

            // Compute mean position.
            let points = sortedSeries.map { $0.point }
            let meanPoint = CGPoint(
                x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
                y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
            )

            // Compute covariance to determine the principal axis.
            var covXX: CGFloat = 0, covXY: CGFloat = 0, covYY: CGFloat = 0
            for p in points {
                let dx = p.x - meanPoint.x
                let dy = p.y - meanPoint.y
                covXX += dx * dx
                covXY += dx * dy
                covYY += dy * dy
            }
            let n = CGFloat(points.count)
            covXX /= n; covXY /= n; covYY /= n

            let angle = 0.5 * atan2(2 * covXY, covXX - covYY)
            let principalAxis = CGPoint(x: cos(angle), y: sin(angle))

            // Project each point onto the principal axis.
            var projectedSignal: [(timestamp: Double, value: CGFloat)] = []
            for (timestamp, point) in sortedSeries {
                let dx = point.x - meanPoint.x
                let dy = point.y - meanPoint.y
                let projection = dx * principalAxis.x + dy * principalAxis.y
                projectedSignal.append((timestamp: timestamp, value: projection))
            }

            // Smooth the projected signal.
            let smoothedSignal = movingAverage(signal: projectedSignal, windowSize: 5)

            print("🔍 Type: \(jointType)")
            // Detect rep cycles from the smoothed signal.
            let cycles = detectReps(from: smoothedSignal)
            if !cycles.isEmpty {
                let data = JointCycleData(keypointType: jointType, cycles: cycles, smoothedSignal: smoothedSignal)
                jointCycleDataList.append(data)
            }
        }

        // If no joint produced cycles, return an empty set.
        guard !jointCycleDataList.isEmpty else { return [] }

        for data in jointCycleDataList {
            print("🔍 Type: \(data.keypointType), amplitude: \(data.cycles.map { $0.amplitude }.reduce(0, +) / CGFloat(data.cycles.count))")
        }

        // Select the joint with the highest average cycle amplitude.
        let bestJointData = jointCycleDataList.max { lhs, rhs in
            let lhsAvg = lhs.cycles.map { $0.amplitude }.reduce(0, +) / CGFloat(lhs.cycles.count)
            let rhsAvg = rhs.cycles.map { $0.amplitude }.reduce(0, +) / CGFloat(rhs.cycles.count)
            return lhsAvg < rhsAvg
        }!

        // Group the cycles from the selected joint into exercise sets.
        let setGapThreshold = 2.0 // seconds between sets
        var detectedSets: [DetectedExerciseSet] = []
        let cycles = bestJointData.cycles.sorted { $0.startTime < $1.startTime }
        if !cycles.isEmpty {
            var currentSetStart = cycles.first!.startTime
            var currentSetEnd = cycles.first!.endTime
            var repCount = 1
            for cycle in cycles.dropFirst() {
                let gap = cycle.startTime - currentSetEnd
                if gap > setGapThreshold {
                    detectedSets.append(DetectedExerciseSet(reps: repCount, startTime: currentSetStart,
                                                            endTime: currentSetEnd,
                                                            keyJoint: bestJointData.keypointType.rawValue))
                    currentSetStart = cycle.startTime
                    repCount = 1
                } else {
                    repCount += 1
                }
                currentSetEnd = cycle.endTime
            }
            detectedSets.append(DetectedExerciseSet(reps: repCount, startTime: currentSetStart,
                                                    endTime: currentSetEnd,
                                                    keyJoint: bestJointData.keypointType.rawValue))
        }

        return detectedSets
    }

    // MARK: - Helper Functions

    /// Applies a simple moving average to smooth the signal.
    private func movingAverage(signal: [(timestamp: Double, value: CGFloat)], windowSize: Int) -> [(timestamp: Double, value: CGFloat)] {
        guard windowSize > 0, !signal.isEmpty else { return signal }
        var smoothed: [(timestamp: Double, value: CGFloat)] = []
        let halfWindow = windowSize / 2
        for i in 0 ..< signal.count {
            let start = max(0, i - halfWindow)
            let end = min(signal.count - 1, i + halfWindow)
            let window = signal[start ... end]
            let averageValue = window.map { $0.value }.reduce(0, +) / CGFloat(window.count)
            smoothed.append((timestamp: signal[i].timestamp, value: averageValue))
        }
        return smoothed
    }

    /// Detects rep cycles from the smoothed 1D signal by finding local minima-to-minima cycles that contain a peak.
    /// Returns cycles that include an amplitude measure. Also includes a tolerance check for matching start/end values.
    /// For a two-rep scenario, a more lenient tolerance is used.
    private func detectReps(from signal: [(timestamp: Double, value: CGFloat)]) -> [RepCycle] {
        guard signal.count >= 3 else { return [] }

        var minimaIndices: [Int] = []
        var maximaIndices: [Int] = []

        // Identify local minima and maxima.
        for i in 1 ..< signal.count - 1 {
            if signal[i].value < signal[i - 1].value, signal[i].value < signal[i + 1].value {
                minimaIndices.append(i)
            }
            if signal[i].value > signal[i - 1].value, signal[i].value > signal[i + 1].value {
                maximaIndices.append(i)
            }
        }

        // Compute the global range for amplitude and tolerance calculations.
        let globalMax = signal.map { $0.value }.max() ?? 0
        let globalMin = signal.map { $0.value }.min() ?? 0
        let globalRange = globalMax - globalMin

        // Determine if we are in a "two-rep" scenario.
        let repCycleCount = max(0, minimaIndices.count - 1)
        let toleranceFraction: CGFloat = (repCycleCount == 2) ? 0.1 : 0.05
        let toleranceThreshold = toleranceFraction * globalRange

        var cycles: [RepCycle] = []
        print(" 🔍 Minima: \(minimaIndices), Maxima: \(maximaIndices)")

        // Form cycles from one minimum to the next with a peak in between.
        for i in 0 ..< minimaIndices.count - 1 {
            let startIndex = minimaIndices[i]
            let endIndex = minimaIndices[i + 1]

            // Ensure start and end values are nearly the same.
            let startValue = signal[startIndex].value
            let endValue = signal[endIndex].value
            if abs(startValue - endValue) > toleranceThreshold {
                print(" 🔍 Start: \(startValue), End: \(endValue), Tolerance: \(toleranceThreshold)")
                continue
            }

            // Look for a maximum between these minima.
            let candidateMaxima = maximaIndices.filter { $0 > startIndex && $0 < endIndex }
            guard let peakIndex = candidateMaxima.max(by: { signal[$0].value < signal[$1].value }) else { print(" 🔍 No peak found"); continue }

            // Calculate amplitude as the difference between the peak and the lower of the two minima.
            let amplitude = signal[peakIndex].value - min(startValue, endValue)
            // Require a minimum amplitude change.
            if amplitude >= 0.1 * globalRange {
                let cycle = RepCycle(startTime: signal[startIndex].timestamp,
                                     peakTime: signal[peakIndex].timestamp,
                                     endTime: signal[endIndex].timestamp,
                                     amplitude: amplitude)
                cycles.append(cycle)
            } else {
                print(" 🔍 Amplitude: \(amplitude), Global Range: \(globalRange)")
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
