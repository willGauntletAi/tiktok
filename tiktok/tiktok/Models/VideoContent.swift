import FirebaseFirestore
import Foundation

protocol VideoContent: Identifiable, Codable, Hashable, EmptyInitializable {
  var id: String { get set }
  var type: String { get set }
  var title: String { get set }
  var description: String { get set }
  var instructorId: String { get set }
  var videoUrl: String { get set }
  var thumbnailUrl: String { get set }
  var difficulty: Difficulty { get set }
  var targetMuscles: [String] { get set }
  var createdAt: Date { get set }
  var updatedAt: Date { get set }

  var dictionary: [String: Any] { get }
}

// Default implementation for dictionary
extension VideoContent {
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
      "createdAt": Timestamp(date: createdAt),
      "updatedAt": Timestamp(date: updatedAt),
    ]
  }
}
