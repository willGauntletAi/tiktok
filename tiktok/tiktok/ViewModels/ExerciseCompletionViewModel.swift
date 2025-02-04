import FirebaseAuth
import FirebaseFirestore
import Foundation

struct ExerciseCompletion: Identifiable {
  let id: String
  let repsCompleted: Int
  let weight: Double?
  let notes: String
  let completedAt: Date
}

@MainActor
class ExerciseCompletionViewModel: ObservableObject {
  @Published var recentCompletions: [ExerciseCompletion] = []
  @Published var isLoadingHistory = false
  @Published var hasMoreHistory = false
  @Published var errorMessage: String?

  private let exerciseId: String
  private let db = Firestore.firestore()
  private var lastDocument: DocumentSnapshot?

  init(exerciseId: String) {
    self.exerciseId = exerciseId
  }

  func fetchRecentCompletions() async {
    guard let userId = Auth.auth().currentUser?.uid else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let query = db.collection("exerciseCompletions")
        .whereField("exerciseId", isEqualTo: exerciseId)
        .whereField("userId", isEqualTo: userId)
        .order(by: "completedAt", descending: true)
        .limit(to: 4)  // Fetch 4 to know if there are more

      let snapshot = try await query.getDocuments()

      // If we have more than 3 documents, there's more history
      hasMoreHistory = snapshot.documents.count > 3

      // Only take the first 3 documents for display
      let documents = Array(snapshot.documents.prefix(3))
      lastDocument = documents.last

      recentCompletions = documents.compactMap { doc -> ExerciseCompletion? in
        let data = doc.data()
        guard let repsCompleted = data["repsCompleted"] as? Int,
          let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        else {
          return nil
        }

        return ExerciseCompletion(
          id: doc.documentID,
          repsCompleted: repsCompleted,
          weight: data["weight"] as? Double,
          notes: data["notes"] as? String ?? "",
          completedAt: completedAt
        )
      }
    } catch {
      errorMessage = "Failed to load history: \(error.localizedDescription)"
    }
  }

  func fetchMoreHistory() async {
    guard let userId = Auth.auth().currentUser?.uid,
      let lastDoc = lastDocument
    else { return }

    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let query = db.collection("exerciseCompletions")
        .whereField("exerciseId", isEqualTo: exerciseId)
        .whereField("userId", isEqualTo: userId)
        .order(by: "completedAt", descending: true)
        .start(afterDocument: lastDoc)
        .limit(to: 10)

      let snapshot = try await query.getDocuments()
      lastDocument = snapshot.documents.last
      hasMoreHistory = !snapshot.documents.isEmpty

      let newCompletions = snapshot.documents.compactMap { doc -> ExerciseCompletion? in
        let data = doc.data()
        guard let repsCompleted = data["repsCompleted"] as? Int,
          let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        else {
          return nil
        }

        return ExerciseCompletion(
          id: doc.documentID,
          repsCompleted: repsCompleted,
          weight: data["weight"] as? Double,
          notes: data["notes"] as? String ?? "",
          completedAt: completedAt
        )
      }

      recentCompletions.append(contentsOf: newCompletions)
    } catch {
      errorMessage = "Failed to load more history: \(error.localizedDescription)"
    }
  }
}
