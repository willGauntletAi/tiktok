import FirebaseFirestore
import Foundation

struct WorkoutPlan: Identifiable {
  var id: String
  var type: String
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
    return [
      "id": id,
      "type": type,
      "title": title,
      "description": description,
      "instructorId": instructorId,
      "videoUrl": videoUrl,
      "thumbnailUrl": thumbnailUrl,
      "difficulty": difficulty.rawValue,
      "targetMuscles": targetMuscles,
      "workouts": workouts,
      "duration": duration,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
    ]
  }
}
