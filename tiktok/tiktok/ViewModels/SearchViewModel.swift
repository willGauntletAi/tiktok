import FirebaseFirestore
import Foundation

enum ContentType: String, CaseIterable {
  case exercise = "exercise"
  case workout = "workout"
  case workoutPlan = "workoutPlan"

  var displayName: String {
    switch self {
    case .exercise: return "Exercise"
    case .workout: return "Workout"
    case .workoutPlan: return "Workout Plan"
    }
  }
}

@MainActor
class SearchViewModel: ObservableObject {
  @Published var exercises: [Exercise] = []
  @Published var workouts: [Workout] = []
  @Published var workoutPlans: [WorkoutPlan] = []
  @Published var selectedMuscles: Set<String> = []
  @Published var selectedDifficulty: Difficulty?
  @Published var selectedContentType: ContentType = .exercise
  @Published var searchText: String = ""

  private let db = Firestore.firestore()

  let muscleGroups = [
    "Chest", "Back", "Shoulders", "Biceps", "Triceps",
    "Legs", "Core", "Full Body",
  ]

  let difficultyLevels = Difficulty.allCases

  func search() async {
    switch selectedContentType {
    case .exercise:
      await searchExercises()
    case .workout:
      await searchWorkouts()
    case .workoutPlan:
      await searchWorkoutPlans()
    }
  }

  private func searchExercises() async {
    do {
      var query = db.collection("videos")
        .whereField("type", isEqualTo: ContentType.exercise.rawValue)

      if !selectedMuscles.isEmpty {
        query = query.whereField("targetMuscles", arrayContainsAny: Array(selectedMuscles))
      }

      if let difficulty = selectedDifficulty {
        query = query.whereField("difficulty", isEqualTo: difficulty.rawValue)
      }

      if !searchText.isEmpty {
        query = query.whereField("title", isGreaterThanOrEqualTo: searchText)
          .whereField("title", isLessThan: searchText + "z")
      }

      let snapshot = try await query.getDocuments()
      exercises = snapshot.documents.compactMap { document in
        try? document.data(as: Exercise.self)
      }
      workouts = []
      workoutPlans = []
    } catch {
      print("Error fetching exercises: \(error)")
      exercises = []
    }
  }

  private func searchWorkouts() async {
    do {
      var query = db.collection("videos")
        .whereField("type", isEqualTo: ContentType.workout.rawValue)

      if !selectedMuscles.isEmpty {
        query = query.whereField("targetMuscles", arrayContainsAny: Array(selectedMuscles))
      }

      if let difficulty = selectedDifficulty {
        query = query.whereField("difficulty", isEqualTo: difficulty.rawValue)
      }

      if !searchText.isEmpty {
        query = query.whereField("title", isGreaterThanOrEqualTo: searchText)
          .whereField("title", isLessThan: searchText + "z")
      }

      let snapshot = try await query.getDocuments()
      workouts = snapshot.documents.compactMap { document in
        do {
          let workout = try document.data(as: Workout.self)
          return workout
        } catch {
          print("Error parsing workout document: \(error)")
          return nil
        }
      }
      exercises = []
      workoutPlans = []
    } catch {
      print("Error fetching workouts: \(error)")
      workouts = []
    }
  }

  private func searchWorkoutPlans() async {
    do {
      var query = db.collection("videos")
        .whereField("type", isEqualTo: ContentType.workoutPlan.rawValue)

      if !selectedMuscles.isEmpty {
        query = query.whereField("targetMuscles", arrayContainsAny: Array(selectedMuscles))
      }

      if let difficulty = selectedDifficulty {
        query = query.whereField("difficulty", isEqualTo: difficulty.rawValue)
      }

      if !searchText.isEmpty {
        query = query.whereField("title", isGreaterThanOrEqualTo: searchText)
          .whereField("title", isLessThan: searchText + "z")
      }

      let snapshot = try await query.getDocuments()
      workoutPlans = snapshot.documents.compactMap { document in
        try? document.data(as: WorkoutPlan.self)
      }
      exercises = []
      workouts = []
    } catch {
      print("Error fetching workout plans: \(error)")
      workoutPlans = []
    }
  }

  func toggleMuscle(_ muscle: String) {
    if selectedMuscles.contains(muscle) {
      selectedMuscles.remove(muscle)
    } else {
      selectedMuscles.insert(muscle)
    }
    Task {
      await search()
    }
  }

  func setDifficulty(_ difficulty: Difficulty?) {
    selectedDifficulty = difficulty
    Task {
      await search()
    }
  }

  func setContentType(_ type: ContentType) {
    selectedContentType = type
    Task {
      await search()
    }
  }
}
