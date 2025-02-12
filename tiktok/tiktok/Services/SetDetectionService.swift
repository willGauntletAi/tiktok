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
        print("🏃‍♂️ Starting set detection with \(poseResults.count) pose results")
        guard !poseResults.isEmpty else {
            print("❌ No pose results to analyze")
            return []
        }

        // Convert PoseResults to frames (dictionary mapping joint names to positions and confidences)
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
        print("📊 Converted \(frames.count) frames for analysis")

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
        print("🔑 Selected key joint: \(keyJoint) with \(cycles.count) cycles")
        print("🦴 Joint details:")
        if let keypointType = KeypointType(rawValue: keyJoint) {
            print("  Type: \(keypointType)")
            print("  Side: \(keypointType.rawValue.hasPrefix("left") ? "Left" : keypointType.rawValue.hasPrefix("right") ? "Right" : "Center")")
            print("  Body part: \(keypointType.bodyPart)")
        }

        // Log cycle details
        for (i, cycle) in cycles.enumerated() {
            let startTime = poseResults[cycle.startIndex].timestamp
            let peakTime = poseResults[cycle.peakIndex].timestamp
            let endTime = poseResults[cycle.endIndex].timestamp
            let startToEndDistance = abs(distanceSeries[cycle.endIndex] - distanceSeries[cycle.startIndex])
            print("  Rep \(i + 1) using \(keyJoint):")
            print("    Start: \(String(format: "%.2f", startTime))s")
            print("    Peak:  \(String(format: "%.2f", peakTime))s")
            print("    End:   \(String(format: "%.2f", endTime))s")
            print("    Duration: \(String(format: "%.2f", endTime - startTime))s")
            print("    Amplitude: \(String(format: "%.3f", cycle.amplitude)) (threshold: \(String(format: "%.3f", amplitudeThreshold)))")
            print("    Start-End Distance: \(String(format: "%.3f", startToEndDistance)) (tolerance: \(String(format: "%.3f", tolerance)))")
            print("    Average Confidence: \(String(format: "%.2f", cycle.averageConfidence))")
            print("    Movement: \(cycle.isAscending ? "Bottom to Top" : "Top to Bottom")")
            if cycle.amplitude > amplitudeThreshold * 2 {
                print("    ⚠️ Large movement detected - possible form issue")
            } else if cycle.amplitude < amplitudeThreshold * 1.2 {
                print("    ⚠️ Small movement detected - possible partial rep")
            }
            if startToEndDistance > tolerance {
                print("    ⚠️ End position differs from start by \(String(format: "%.3f", startToEndDistance)) - possible incomplete return")
            }
        }

        // Segment the recording into exercise sets based on gaps between cycles
        let segments = segmentSetsBasedOnCycles(cycles: cycles, maxCycleGap: maxCycleGap)
        print("📦 Found \(segments.count) exercise sets")

        // Convert segments to DetectedExerciseSet objects
        let detectedSets = segments.map { segment in
            DetectedExerciseSet(
                reps: segment.cycles.count,
                startTime: poseResults[segment.startIndex].timestamp,
                endTime: poseResults[segment.endIndex].timestamp,
                keyJoint: keyJoint
            )
        }

        // Log set details
        for (i, set) in detectedSets.enumerated() {
            print("Set \(i + 1) using \(set.keyJoint):")
            print("  Reps: \(set.reps)")
            print("  Start Time: \(String(format: "%.2f", set.startTime))s")
            print("  End Time: \(String(format: "%.2f", set.endTime))s")
            print("  Duration: \(String(format: "%.2f", set.endTime - set.startTime))s")

            // Calculate average rep duration for the set
            if set.reps > 0 {
                let avgDuration = (set.endTime - set.startTime) / Double(set.reps)
                print("  Average rep duration: \(String(format: "%.2f", avgDuration))s")
            }
        }

        print("✅ Set detection completed")
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
        let smoothedDistances = smoothDistances(distances)

        print("📏 Computed \(smoothedDistances.count) distances for joint: \(joint)")
        print("   Average confidence: \(String(format: "%.2f", confidences.reduce(0, +) / Float(confidences.count)))")
        return smoothedDistances
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

        print("📉 Found \(minima.count) minima and \(maxima.count) maxima in distance series")

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

        // Process each potential cycle
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
                    // Complete bottom-to-top-to-bottom cycle
                    let amplitude = distanceSeries[cyclePeak] - distanceSeries[cycleStart]
                    let startToEndDistance = abs(distanceSeries[i] - distanceSeries[cycleStart])

                    // Only count as valid rep if amplitude meets threshold AND end position is close to start
                    if amplitude >= amplitudeThreshold, startToEndDistance <= tolerance {
                        cycles.append(Cycle(
                            startIndex: cycleStart,
                            peakIndex: cyclePeak,
                            endIndex: i,
                            amplitude: amplitude,
                            averageConfidence: 0.8, // TODO: Calculate actual confidence
                            isAscending: true
                        ))
                        print("✅ Valid ascending cycle detected: amplitude = \(String(format: "%.3f", amplitude)), start-end distance = \(String(format: "%.3f", startToEndDistance))")
                    } else {
                        if amplitude < amplitudeThreshold {
                            print("⚠️ Cycle rejected: insufficient amplitude (\(String(format: "%.3f", amplitude)))")
                        }
                        if startToEndDistance > tolerance {
                            print("⚠️ Cycle rejected: incomplete return (\(String(format: "%.3f", startToEndDistance)))")
                        }
                    }
                    cycleStart = i
                    currentPhase = .ascending
                } else if !startsFromBottom, maxima.contains(i) {
                    // Complete top-to-bottom-to-top cycle
                    let amplitude = distanceSeries[cycleStart] - distanceSeries[cyclePeak]
                    let startToEndDistance = abs(distanceSeries[i] - distanceSeries[cycleStart])

                    // Only count as valid rep if amplitude meets threshold AND end position is close to start
                    if amplitude >= amplitudeThreshold, startToEndDistance <= tolerance {
                        cycles.append(Cycle(
                            startIndex: cycleStart,
                            peakIndex: cyclePeak,
                            endIndex: i,
                            amplitude: amplitude,
                            averageConfidence: 0.8, // TODO: Calculate actual confidence
                            isAscending: false
                        ))
                        print("✅ Valid descending cycle detected: amplitude = \(String(format: "%.3f", amplitude)), start-end distance = \(String(format: "%.3f", startToEndDistance))")
                    } else {
                        if amplitude < amplitudeThreshold {
                            print("⚠️ Cycle rejected: insufficient amplitude (\(String(format: "%.3f", amplitude)))")
                        }
                        if startToEndDistance > tolerance {
                            print("⚠️ Cycle rejected: incomplete return (\(String(format: "%.3f", startToEndDistance)))")
                        }
                    }
                    cycleStart = i
                    currentPhase = .descending
                }

            case .returning:
                break // Handled in peak phase
            }
        }

        print("🔄 Detected \(cycles.count) valid cycles")
        return cycles
    }

    private func segmentSetsBasedOnCycles(cycles: [Cycle], maxCycleGap: Int) -> [ExerciseSegment] {
        var segments: [ExerciseSegment] = []
        guard !cycles.isEmpty else {
            print("⚠️ No cycles to segment")
            return segments
        }

        var currentCycles: [Cycle] = [cycles[0]]
        for i in 1 ..< cycles.count {
            let previousCycle = cycles[i - 1]
            let currentCycle = cycles[i]
            let gap = currentCycle.startIndex - previousCycle.endIndex
            if gap > maxCycleGap {
                // End the current segment and start a new one
                print("📋 Starting new set: gap of \(gap) frames exceeded maximum of \(maxCycleGap)")
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

        print("🔍 Analyzing \(candidateJoints.count) candidate joints")
        var bestCandidate: (joint: String, cycles: [Cycle], distanceSeries: [Double])?

        for joint in candidateJoints {
            print("\n📊 Analyzing joint: \(joint)")
            let distanceSeries = computeDistanceSeries(for: joint, frames: frames)
            let cycles = detectCycles(distanceSeries: distanceSeries,
                                      amplitudeThreshold: amplitudeThreshold,
                                      tolerance: tolerance)

            // Choose the joint that produces the most valid cycles
            if let best = bestCandidate {
                if cycles.count > best.cycles.count {
                    print("🔄 New best joint found: \(joint) with \(cycles.count) cycles (previous best: \(best.joint) with \(best.cycles.count) cycles)")
                    bestCandidate = (joint, cycles, distanceSeries)
                }
            } else {
                print("🔄 First candidate: \(joint) with \(cycles.count) cycles")
                bestCandidate = (joint, cycles, distanceSeries)
            }
        }

        if let best = bestCandidate {
            print("✅ Selected key joint: \(best.joint) with \(best.cycles.count) cycles")
        } else {
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
