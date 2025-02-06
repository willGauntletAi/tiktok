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
        id = document.documentID
        let data = document.data() ?? [:]
        workoutId = data["workoutId"] as? String ?? ""
        userId = data["userId"] as? String ?? ""
        exerciseCompletions = data["exerciseCompletions"] as? [String] ?? []
        startedAt = (data["startedAt"] as? Timestamp)?.dateValue() ?? Date()
        finishedAt = (data["finishedAt"] as? Timestamp)?.dateValue()
        notes = data["notes"] as? String ?? ""
    }
}
