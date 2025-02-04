import FirebaseFirestore
import Foundation

class WorkoutCompletionViewModel: ObservableObject {
  let workoutId: String
  @Published var isLoadingHistory = false
  @Published var recentCompletions: [WorkoutCompletion] = []
  @Published var hasMoreHistory = false
  private var lastDocument: DocumentSnapshot?
  private let pageSize = 5

  init(workoutId: String) {
    self.workoutId = workoutId
  }

  @MainActor
  func fetchRecentCompletions() async {
    guard !isLoadingHistory else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let db = Firestore.firestore()
      var query = db.collection("workoutCompletions")
        .whereField("workoutId", isEqualTo: workoutId)
        .order(by: "startedAt", descending: true)
        .limit(to: pageSize)

      let snapshot = try await query.getDocuments()
      lastDocument = snapshot.documents.last

      recentCompletions = snapshot.documents.compactMap { document in
        let data = document.data()
        return WorkoutCompletion(document: document)
      }

      hasMoreHistory = !snapshot.documents.isEmpty && snapshot.documents.count == pageSize
    } catch {
      print("Error fetching workout completions: \(error)")
    }
  }

  @MainActor
  func fetchMoreHistory() async {
    guard !isLoadingHistory, hasMoreHistory, let lastDocument = lastDocument else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let db = Firestore.firestore()
      let query = db.collection("workoutCompletions")
        .whereField("workoutId", isEqualTo: workoutId)
        .order(by: "startedAt", descending: true)
        .limit(to: pageSize)
        .start(afterDocument: lastDocument)

      let snapshot = try await query.getDocuments()
      self.lastDocument = snapshot.documents.last

      let newCompletions = snapshot.documents.compactMap { document in
        WorkoutCompletion(document: document)
      }

      recentCompletions.append(contentsOf: newCompletions)
      hasMoreHistory = !snapshot.documents.isEmpty && snapshot.documents.count == pageSize
    } catch {
      print("Error fetching more workout completions: \(error)")
    }
  }
}
