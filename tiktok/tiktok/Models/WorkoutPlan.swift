import FirebaseFirestore
import Foundation

struct WorkoutPlan: VideoContent {
  var id: String
  var type: String = "workoutPlan"
  var title: String
  var description: String
  var instructorId: String
  var videoUrl: String
  var thumbnailUrl: String
  var difficulty: Difficulty
  var targetMuscles: [String]
  var workouts: [String]  // Array of workout IDs
  var duration: Int  // in days
  var createdAt: Date
  var updatedAt: Date

  var dictionary: [String: Any] {
    var dict: [String: Any] = [
      "id": id,
      "type": type,
      "title": title,
      "description": description,
      "instructorId": instructorId,
      "videoUrl": videoUrl,
      "thumbnailUrl": thumbnailUrl,
      "difficulty": difficulty.rawValue,
      "targetMuscles": targetMuscles,
      "createdAt": Timestamp(date: createdAt),
      "updatedAt": Timestamp(date: updatedAt),
    ]
    dict["workouts"] = workouts
    dict["duration"] = duration
    return dict
  }

  static func empty() -> WorkoutPlan {
    WorkoutPlan(
      id: UUID().uuidString,
      title: "",
      description: "",
      instructorId: "",
      videoUrl: "",
      thumbnailUrl: "",
      difficulty: .beginner,
      targetMuscles: [],
      workouts: [],
      duration: 7,  // Default to 7 days
      createdAt: Date(),
      updatedAt: Date()
    )
  }
}
