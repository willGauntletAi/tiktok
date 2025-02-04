import FirebaseFirestore
import Foundation

@MainActor
class SearchViewModel: ObservableObject {
  @Published var exercises: [Exercise] = []
  @Published var selectedMuscles: Set<String> = []
  @Published var selectedDifficulty: String?

  private let db = Firestore.firestore()

  let muscleGroups = [
    "Chest", "Back", "Shoulders", "Biceps", "Triceps",
    "Legs", "Core", "Full Body",
  ]

  let difficultyLevels = ["beginner", "intermediate", "advanced"]

  func searchExercises() async {
    do {
      var query = db.collection("videos")
        .whereField("type", isEqualTo: "exercise")

      if !selectedMuscles.isEmpty {
        query = query.whereField("targetMuscles", arrayContainsAny: Array(selectedMuscles))
      }

      if let difficulty = selectedDifficulty {
        query = query.whereField("difficulty", isEqualTo: difficulty)
      }

      let snapshot = try await query.getDocuments()
      exercises = snapshot.documents.compactMap { document in
        try? document.data(as: Exercise.self)
      }
    } catch {
      print("Error fetching exercises: \(error)")
    }
  }

  func toggleMuscle(_ muscle: String) {
    if selectedMuscles.contains(muscle) {
      selectedMuscles.remove(muscle)
    } else {
      selectedMuscles.insert(muscle)
    }
    Task {
      await searchExercises()
    }
  }

  func setDifficulty(_ difficulty: String?) {
    selectedDifficulty = difficulty
    Task {
      await searchExercises()
    }
  }
}
