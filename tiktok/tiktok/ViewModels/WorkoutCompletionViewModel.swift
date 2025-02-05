import FirebaseAuth
import FirebaseFirestore
import Foundation

struct ExerciseState {
  var sets: [ExerciseSet]
  var isLoading: Bool
  var showError: Bool
  var errorMessage: String
}

@MainActor
class WorkoutCompletionViewModel: ObservableObject {
  let workoutId: String
  @Published var isLoadingHistory = false
  @Published var recentCompletions: [WorkoutCompletion] = []
  @Published var hasMoreHistory = false

  // Active workout state
  @Published var isStarted = false
  @Published var startTime: Date?
  @Published var isLoading = false
  @Published var showError = false
  @Published var errorMessage = ""
  @Published var workoutCompletionId: String?
  @Published var exerciseStates: [String: ExerciseState] = [:]

  private var lastDocument: DocumentSnapshot?
  private let pageSize = 5
  private let db = Firestore.firestore()

  init(workoutId: String, workout: Workout) {
    self.workoutId = workoutId
    // Initialize exercise states
    let initialStates = workout.exercises.reduce(into: [:]) { dict, exercise in
      dict[exercise.id] = ExerciseState(
        sets: [ExerciseSet(reps: 0, weight: nil, notes: "")],
        isLoading: false,
        showError: false,
        errorMessage: ""
      )
    }
    self.exerciseStates = initialStates
  }

  func startWorkout() async throws {
    isLoading = true
    defer { isLoading = false }

    guard let userId = Auth.auth().currentUser?.uid else {
      throw NSError(
        domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
    }

    let workoutCompletion =
      [
        "workoutId": workoutId,
        "userId": userId,
        "exerciseCompletions": [],
        "startedAt": Timestamp(),
        "notes": "",
      ] as [String: Any]

    let docRef = try await db.collection("workoutCompletions").addDocument(data: workoutCompletion)
    workoutCompletionId = docRef.documentID
    startTime = Date()
    isStarted = true
  }

  func cancelWorkout() async throws {
    isLoading = true
    defer { isLoading = false }

    if let workoutCompletionId = workoutCompletionId {
      try await db.collection("workoutCompletions").document(workoutCompletionId).delete()
      self.workoutCompletionId = nil
      isStarted = false
      startTime = nil
    }
  }

  func checkWorkoutCompletion() async throws {
    guard let workoutCompletionId = workoutCompletionId else { return }

    let snapshot = try await db.collection("exerciseCompletions")
      .whereField("workoutCompletionId", isEqualTo: workoutCompletionId)
      .getDocuments()

    let completedExercises = Set(
      snapshot.documents.map { $0.data()["exerciseId"] as? String ?? "" })
    let allExercises = Set(exerciseStates.keys)

    if completedExercises == allExercises {
      try await db.collection("workoutCompletions").document(workoutCompletionId).updateData([
        "finishedAt": Timestamp()
      ])
    }
  }

  @MainActor
  func fetchRecentCompletions() async {
    guard !isLoadingHistory else { return }
    isLoadingHistory = true
    defer { isLoadingHistory = false }

    do {
      let query = db.collection("workoutCompletions")
        .whereField("workoutId", isEqualTo: workoutId)
        .order(by: "startedAt", descending: true)
        .limit(to: pageSize)

      let snapshot = try await query.getDocuments()
      lastDocument = snapshot.documents.last

      recentCompletions = snapshot.documents.compactMap { document in
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
