import Foundation
import FirebaseFirestore

enum Difficulty: String, CaseIterable, Codable {
    case beginner
    case intermediate
    case advanced
}

struct Exercise: Identifiable, Codable {
    var id: String
    var type: String = "exercise"
    var title: String
    var description: String
    var instructorId: String
    var videoUrl: String
    var thumbnailUrl: String
    var difficulty: Difficulty
    var targetMuscles: [String]
    var duration: Int  // in seconds
    var sets: Int?
    var reps: Int?
    var createdAt: Date
    var updatedAt: Date
    
    static func empty() -> Exercise {
        Exercise(
            id: UUID().uuidString,
            title: "",
            description: "",
            instructorId: "",
            videoUrl: "",
            thumbnailUrl: "",
            difficulty: .beginner,
            targetMuscles: [],
            duration: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
} 