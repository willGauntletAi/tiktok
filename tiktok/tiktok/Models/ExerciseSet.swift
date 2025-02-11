import Foundation

struct ExerciseSet: Identifiable, Codable {
    let id: UUID
    let reps: Int
    let startTime: Double  // Time in seconds from start of clip
    let endTime: Double    // Time in seconds from start of clip
    
    init(id: UUID = UUID(), reps: Int, startTime: Double, endTime: Double) {
        self.id = id
        self.reps = reps
        self.startTime = startTime
        self.endTime = endTime
    }
}

typealias ExerciseSets = [ExerciseSet]
