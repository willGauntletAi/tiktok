import FirebaseFirestore
import Foundation

struct WorkoutCompletion: Identifiable {
  let id: String
  let workoutId: String
  let userId: String
  let exerciseCompletions: [String]
  let startedAt: Date
  let finishedAt: Date?
  let notes: String

  init(document: DocumentSnapshot) {
    self.id = document.documentID
    let data = document.data() ?? [:]
    self.workoutId = data["workoutId"] as? String ?? ""
    self.userId = data["userId"] as? String ?? ""
    self.exerciseCompletions = data["exerciseCompletions"] as? [String] ?? []
    self.startedAt = (data["startedAt"] as? Timestamp)?.dateValue() ?? Date()
    self.finishedAt = (data["finishedAt"] as? Timestamp)?.dateValue()
    self.notes = data["notes"] as? String ?? ""
  }
}
