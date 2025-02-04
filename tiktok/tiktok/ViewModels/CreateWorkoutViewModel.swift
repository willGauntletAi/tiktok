import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class CreateWorkoutViewModel: ObservableObject {
  @Published var workout: Workout
  @Published var selectedExercises: [Exercise] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var showExerciseSelector = false

  private let db = Firestore.firestore()

  init() {
    self.workout = Workout.empty()
  }

  var canSave: Bool {
    !workout.title.isEmpty && !workout.description.isEmpty && !selectedExercises.isEmpty
      && workout.difficulty != nil
  }

  func addExercise(_ exercise: Exercise) {
    if !selectedExercises.contains(where: { $0.id == exercise.id }) {
      selectedExercises.append(exercise)
      updateTotalDuration()
    }
  }

  func removeExercise(at offsets: IndexSet) {
    selectedExercises.remove(atOffsets: offsets)
    updateTotalDuration()
  }

  func moveExercise(from source: IndexSet, to destination: Int) {
    selectedExercises.move(fromOffsets: source, toOffset: destination)
  }

  private func updateTotalDuration() {
    workout.totalDuration = selectedExercises.reduce(0) { $0 + $1.duration }
  }

  func saveWorkout() async {
    guard let userId = Auth.auth().currentUser?.uid else {
      errorMessage = "User not authenticated"
      return
    }

    isLoading = true
    errorMessage = nil

    do {
      // Create workout document
      workout.type = "workout"
      workout.instructorId = userId
      workout.exercises = selectedExercises.map { $0.id }
      workout.createdAt = Date()
      workout.updatedAt = Date()

      let workoutRef = db.collection("videos").document()
      workout.id = workoutRef.documentID

      try await workoutRef.setData(workout.dictionary)

      // Reset form
      self.workout = Workout.empty()
      self.selectedExercises = []

    } catch {
      errorMessage = "Failed to save workout: \(error.localizedDescription)"
    }

    isLoading = false
  }
}
