import FirebaseFirestore
import Foundation

struct Workout: Identifiable, Codable {
  var id: String
  var type: String = "workout"
  var title: String
  var description: String
  var instructorId: String
  var videoUrl: String
  var thumbnailUrl: String
  var difficulty: Difficulty
  var targetMuscles: [String]
  var exercises: [String]  // exercise IDs in order
  var totalDuration: Int  // in seconds
  var createdAt: Date
  var updatedAt: Date

  static func empty() -> Workout {
    Workout(
      id: UUID().uuidString,
      title: "",
      description: "",
      instructorId: "",
      videoUrl: "",
      thumbnailUrl: "",
      difficulty: .beginner,
      targetMuscles: [],
      exercises: [],
      totalDuration: 0,
      createdAt: Date(),
      updatedAt: Date()
    )
  }

  var dictionary: [String: Any] {
    [
      "id": id,
      "type": type,
      "title": title,
      "description": description,
      "instructorId": instructorId,
      "videoUrl": videoUrl,
      "thumbnailUrl": thumbnailUrl,
      "difficulty": difficulty.rawValue,
      "targetMuscles": targetMuscles,
      "exercises": exercises,
      "totalDuration": totalDuration,
      "createdAt": Timestamp(date: createdAt),
      "updatedAt": Timestamp(date: updatedAt),
    ]
  }
}
