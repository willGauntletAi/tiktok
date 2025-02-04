import FirebaseFirestore
import Foundation

@MainActor
class FindExerciseViewModel: ObservableObject {
  @Published var exercises: [Exercise] = []
  @Published var searchText: String = ""
  @Published var instructorEmail: String = ""
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?

  private let db = Firestore.firestore()

  func searchExercises() async {
    isLoading = true
    errorMessage = nil

    do {
      var instructorIds: [String] = []

      // If instructor email is provided, first find the instructor's ID
      if !instructorEmail.isEmpty {
        let usersSnapshot = try await db.collection("users")
          .whereField("email", isEqualTo: instructorEmail.lowercased())
          .getDocuments()

        instructorIds = usersSnapshot.documents.map { $0.documentID }

        // If no instructor found with that email, return empty results
        if instructorIds.isEmpty {
          exercises = []
          isLoading = false
          return
        }
      }

      // Build the query
      var query = db.collection("videos")
        .whereField("type", isEqualTo: "exercise")

      // Add instructor filter if we found matching instructors
      if !instructorIds.isEmpty {
        query = query.whereField("instructorId", in: instructorIds)
      }

      // Get all exercises that match the instructor filter (if any)
      let snapshot = try await query.getDocuments()

      // Filter by title locally if search text is provided
      let allExercises = snapshot.documents.compactMap { document -> Exercise? in
        try? document.data(as: Exercise.self)
      }

      if !searchText.isEmpty {
        exercises = allExercises.filter { exercise in
          exercise.title.lowercased().contains(searchText.lowercased())
        }
      } else {
        exercises = allExercises
      }

    } catch {
      errorMessage = "Error searching exercises: \(error.localizedDescription)"
      exercises = []
    }

    isLoading = false
  }
}
