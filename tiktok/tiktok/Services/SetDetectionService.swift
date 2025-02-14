import AVFoundation
import Foundation
import Vision

class SetDetectionService {
    // Parameters for set detection
    private let amplitudeThreshold: Double = 0.1 // 10% of screen height movement required
    private let tolerance: Double = 0.05 // 5% of screen height tolerance for baseline
    private let maxCycleGap: Int = 30 // Maximum frames between cycles in the same set (at 10fps = 3 seconds)
    private let minConfidence: Float = 0.3 // Minimum confidence for keypoint tracking
    private let smoothingWindowSize = 5 // Number of frames to use for moving average
    private let minContinuousFrames = 3 // Minimum number of continuous frames with valid tracking

    private enum MovementPhase {
        case initial // Starting position
        case ascending // Moving up from start
        case descending // Moving down from start
        case peak // At maximum displacement
        case returning // Returning to start position
    }

    /// Analyzes pose results to detect exercise sets
    /// - Parameters:
    ///   - poseResults: Array of pose detection results to analyze
    /// - Returns: Array of detected exercise sets
    func detectSets(from poseResults: [PoseResult]) -> [DetectedExerciseSet] {
        guard !poseResults.isEmpty else {
            print("❌ No pose results to analyze")
            return []
        }

        // Convert PoseResults to frames
        let frames: [Frame] = poseResults.map { poseResult in
            var frame: [String: JointData] = [:]
            for keypoint in poseResult.keypoints {
                frame[keypoint.type.rawValue] = JointData(
                    position: keypoint.position,
                    confidence: keypoint.confidence
                )
            }
            return frame
        }

        // Find the key joint and its cycles
        guard let candidate = selectKeyJointAcrossCandidates(frames: frames,
                                                             amplitudeThreshold: amplitudeThreshold,
                                                             tolerance: tolerance)
        else {
            print("❌ No suitable key joint found")
            return []
        }

        let keyJoint = candidate.joint
        let cycles = candidate.cycles
        let distanceSeries = candidate.distanceSeries

        // Log only warnings for cycles
        for (i, cycle) in cycles.enumerated() {
            let startToEndDistance = abs(distanceSeries[cycle.endIndex] - distanceSeries[cycle.startIndex])
            
            if cycle.amplitude > amplitudeThreshold * 2 {
                print("⚠️ Large movement detected - possible form issue")
            } else if cycle.amplitude < amplitudeThreshold * 1.2 {
                print("⚠️ Small movement detected - possible partial rep")
            }
            if startToEndDistance > tolerance {
                print("⚠️ End position differs from start by \(String(format: "%.3f", startToEndDistance)) - possible incomplete return")
            }
        }

        // Segment the recording into exercise sets based on gaps between cycles
        let segments = segmentSetsBasedOnCycles(cycles: cycles, maxCycleGap: maxCycleGap)

        // Convert segments to DetectedExerciseSet objects
        let detectedSets = segments.map { segment in
            DetectedExerciseSet(
                reps: segment.cycles.count,
                startTime: poseResults[segment.startIndex].timestamp,
                endTime: poseResults[segment.endIndex].timestamp,
                keyJoint: keyJoint
            )
        }

        return detectedSets
    }

    // MARK: - Private Helper Methods

    private struct JointData {
        let position: CGPoint
        let confidence: Float
    }

    private typealias Frame = [String: JointData]

    private struct Cycle {
        let startIndex: Int
        let peakIndex: Int
        let endIndex: Int
        let amplitude: Double // Maximum distance from baseline during the cycle
        let averageConfidence: Float // Average confidence during the cycle
        let isAscending: Bool // Whether the movement goes from bottom to top
    }

    private struct ExerciseSegment {
        let startIndex: Int
        let endIndex: Int
        let cycles: [Cycle]
    }

    private func euclideanDistance(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = Double(p1.x - p2.x)
        let dy = Double(p1.y - p2.y)
        return sqrt(dx * dx + dy * dy)
    }

    private func smoothDistances(_ distances: [Double]) -> [Double] {
        guard distances.count >= smoothingWindowSize else { return distances }

        var smoothed = [Double]()
        for i in 0 ..< distances.count {
            let windowStart = max(0, i - smoothingWindowSize / 2)
            let windowEnd = min(distances.count - 1, i + smoothingWindowSize / 2)
            let window = Array(distances[windowStart ... windowEnd])
            let average = window.reduce(0.0, +) / Double(window.count)
            smoothed.append(average)
        }
        return smoothed
    }

    private func computeDistanceSeries(for joint: String, frames: [Frame]) -> [Double] {
        guard let baseline = frames.first?[joint] else {
            print("⚠️ No baseline position found for joint: \(joint)")
            return []
        }

        // First pass: compute raw distances and track confidence
        var distances = [Double]()
        var confidences = [Float]()
        var lastValidPosition = baseline.position
        var continuousValidFrames = 0

        for frame in frames {
            if let data = frame[joint], data.confidence >= minConfidence {
                let distance = euclideanDistance(data.position, baseline.position)
                distances.append(distance)
                confidences.append(data.confidence)
                lastValidPosition = data.position
                continuousValidFrames += 1
            } else {
                // If we don't have enough continuous valid frames, consider this a gap
                if continuousValidFrames < minContinuousFrames {
                    // Use a distance that won't trigger false detection
                    distances.append(0.0)
                } else {
                    // Use last valid position to maintain continuity
                    let distance = euclideanDistance(lastValidPosition, baseline.position)
                    distances.append(distance)
                }
                confidences.append(0.0)
                continuousValidFrames = 0
            }
        }

        // Second pass: smooth the distances to reduce noise
        return smoothDistances(distances)
    }

    private func detectCycles(distanceSeries: [Double],
                              amplitudeThreshold: Double,
                              tolerance: Double) -> [Cycle]
    {
        var cycles: [Cycle] = []

        // Find all extrema (both minima and maxima)
        var minima: [Int] = []
        var maxima: [Int] = []
        for i in 1 ..< (distanceSeries.count - 1) {
            let prev = distanceSeries[i - 1]
            let curr = distanceSeries[i]
            let next = distanceSeries[i + 1]

            if curr < prev, curr < next {
                minima.append(i)
            } else if curr > prev, curr > next {
                maxima.append(i)
            }
        }

        // Need at least one minimum and one maximum for a cycle
        guard !minima.isEmpty, !maxima.isEmpty else {
            print("⚠️ Not enough extrema to detect cycles")
            return cycles
        }

        // Analyze the movement pattern
        let firstExtremumIsMin = minima.first! < maxima.first!
        let avgMinValue = minima.map { distanceSeries[$0] }.reduce(0.0, +) / Double(minima.count)
        let avgMaxValue = maxima.map { distanceSeries[$0] }.reduce(0.0, +) / Double(maxima.count)

        // Determine if exercise starts from bottom (ascending) or top (descending)
        let startsFromBottom = firstExtremumIsMin && avgMinValue < avgMaxValue

        // Process each potential cycle using a state machine
        var currentPhase = MovementPhase.initial
        var cycleStart = -1
        var cyclePeak = -1

        for i in 0 ..< distanceSeries.count {
            switch currentPhase {
            case .initial:
                if startsFromBottom, minima.contains(i) {
                    cycleStart = i
                    currentPhase = .ascending
                } else if !startsFromBottom, maxima.contains(i) {
                    cycleStart = i
                    currentPhase = .descending
                }

            case .ascending:
                if maxima.contains(i) {
                    cyclePeak = i
                    currentPhase = .peak
                }

            case .descending:
                if minima.contains(i) {
                    cyclePeak = i
                    currentPhase = .peak
                }

            case .peak:
                if startsFromBottom, minima.contains(i) {
                    let amplitude = distanceSeries[cyclePeak] - distanceSeries[cycleStart]
                    let startToEndDistance = abs(distanceSeries[i] - distanceSeries[cycleStart])
                    // If we're at a boundary (last frame or first rep), relax the tolerance check
                    let isBoundary = (i == distanceSeries.count - 1) || (cycleStart == 0)
                    if amplitude >= amplitudeThreshold, isBoundary || startToEndDistance <= tolerance {
                        cycles.append(Cycle(
                            startIndex: cycleStart,
                            peakIndex: cyclePeak,
                            endIndex: i,
                            amplitude: amplitude,
                            averageConfidence: 0.8, // TODO: Calculate actual confidence
                            isAscending: true
                        ))
                    }
                    cycleStart = i
                    currentPhase = .ascending

                } else if !startsFromBottom, maxima.contains(i) {
                    let amplitude = distanceSeries[cycleStart] - distanceSeries[cyclePeak]
                    let startToEndDistance = abs(distanceSeries[i] - distanceSeries[cycleStart])
                    let isBoundary = (i == distanceSeries.count - 1) || (cycleStart == 0)
                    if amplitude >= amplitudeThreshold, isBoundary || startToEndDistance <= tolerance {
                        cycles.append(Cycle(
                            startIndex: cycleStart,
                            peakIndex: cyclePeak,
                            endIndex: i,
                            amplitude: amplitude,
                            averageConfidence: 0.8, // TODO: Calculate actual confidence
                            isAscending: false
                        ))
                    }
                    cycleStart = i
                    currentPhase = .descending
                }

            case .returning:
                break // This state is not used in the current state machine
            }
        }

        // After iterating through all frames, check if there's an incomplete cycle at the end.
        // This covers cases where the rep did not fully return to baseline.
        if currentPhase != .initial, cycleStart != -1, cyclePeak != -1 {
            let repEndIndex = distanceSeries.count - 1
            let amplitude = startsFromBottom
                ? (distanceSeries[cyclePeak] - distanceSeries[cycleStart])
                : (distanceSeries[cycleStart] - distanceSeries[cyclePeak])
            if amplitude >= amplitudeThreshold {
                cycles.append(Cycle(
                    startIndex: cycleStart,
                    peakIndex: cyclePeak,
                    endIndex: repEndIndex,
                    amplitude: amplitude,
                    averageConfidence: 0.8, // TODO: Calculate actual confidence
                    isAscending: startsFromBottom
                ))
            }
        }

        return cycles
    }

    private func segmentSetsBasedOnCycles(cycles: [Cycle], maxCycleGap: Int) -> [ExerciseSegment] {
        var segments: [ExerciseSegment] = []
        guard !cycles.isEmpty else {
            print("❌ No cycles to segment")
            return segments
        }

        var currentCycles: [Cycle] = [cycles[0]]
        for i in 1 ..< cycles.count {
            let previousCycle = cycles[i - 1]
            let currentCycle = cycles[i]
            let gap = currentCycle.startIndex - previousCycle.endIndex
            if gap > maxCycleGap {
                // End the current segment and start a new one
                let segment = ExerciseSegment(
                    startIndex: currentCycles.first!.startIndex,
                    endIndex: currentCycles.last!.endIndex,
                    cycles: currentCycles
                )
                segments.append(segment)
                currentCycles = [currentCycle]
            } else {
                currentCycles.append(currentCycle)
            }
        }

        // Append the last segment
        if !currentCycles.isEmpty {
            let segment = ExerciseSegment(
                startIndex: currentCycles.first!.startIndex,
                endIndex: currentCycles.last!.endIndex,
                cycles: currentCycles
            )
            segments.append(segment)
        }

        return segments
    }

    private func selectKeyJointAcrossCandidates(frames: [Frame],
                                                amplitudeThreshold: Double,
                                                tolerance: Double) -> (joint: String, cycles: [Cycle], distanceSeries: [Double])?
    {
        guard let candidateJoints = frames.first?.keys else {
            print("❌ No candidate joints found in first frame")
            return nil
        }

        var bestCandidate: (joint: String, cycles: [Cycle], distanceSeries: [Double])?

        for joint in candidateJoints {
            let distanceSeries = computeDistanceSeries(for: joint, frames: frames)
            let cycles = detectCycles(distanceSeries: distanceSeries,
                                      amplitudeThreshold: amplitudeThreshold,
                                      tolerance: tolerance)

            // Choose the joint that produces the most valid cycles
            if let best = bestCandidate {
                if cycles.count > best.cycles.count {
                    bestCandidate = (joint, cycles, distanceSeries)
                }
            } else {
                bestCandidate = (joint, cycles, distanceSeries)
            }
        }

        if bestCandidate == nil {
            print("❌ No suitable key joint found")
        }

        return bestCandidate
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
