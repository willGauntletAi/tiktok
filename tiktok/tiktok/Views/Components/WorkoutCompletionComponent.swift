import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import SwiftUI

struct WorkoutCompletionComponent: View {
  let workout: Workout
  @StateObject private var viewModel: WorkoutCompletionViewModel
  @State private var isStarted = false
  @State private var startTime: Date?
  @State private var isLoading = false
  @State private var showError = false
  @State private var errorMessage = ""
  @State private var workoutCompletionId: String?
  @State private var exerciseStates: [String: ExerciseState] = [:]
  var onComplete: (() -> Void)?

  struct ExerciseState {
    var sets: [ExerciseSet]
    var isLoading: Bool
    var showError: Bool
    var errorMessage: String
  }

  init(workout: Workout, onComplete: (() -> Void)? = nil) {
    self.workout = workout
    self.onComplete = onComplete
    self._viewModel = StateObject(wrappedValue: WorkoutCompletionViewModel(workoutId: workout.id))
    // Initialize exercise states
    let initialStates = workout.exercises.reduce(into: [:]) { dict, exercise in
      dict[exercise.id] = ExerciseState(
        sets: [ExerciseSet(reps: 0, weight: nil, notes: "")],
        isLoading: false,
        showError: false,
        errorMessage: ""
      )
    }
    self._exerciseStates = State(initialValue: initialStates)
  }

  var body: some View {
    VStack(spacing: 20) {
      // Workout Info
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Text("Workout Details")
            .font(.headline)
            .bold()

          Text(workout.title)
            .font(.headline)

          Text(workout.description)
            .font(.subheadline)
            .foregroundColor(.secondary)

          HStack {
            Image(systemName: "clock")
            Text("\(workout.exercises.count) exercises")
          }
          .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal)

      // Start/Cancel Workout Button
      if !isStarted {
        Button(action: {
          Task {
            await startWorkout()
          }
        }) {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Text("Start Workout")
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
        .disabled(isLoading)
        .padding(.horizontal)
      } else {
        Button(action: {
          Task {
            await cancelWorkout()
          }
        }) {
          if isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .red))
          } else {
            Text("Cancel Workout")
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.red)
        .foregroundColor(.white)
        .cornerRadius(10)
        .disabled(isLoading)
        .padding(.horizontal)
      }

      if isStarted {
        // Exercise List
        ForEach(workout.exercises, id: \.id) { exercise in
          let exerciseState =
            exerciseStates[exercise.id]
            ?? ExerciseState(
              sets: [ExerciseSet(reps: 0, weight: nil, notes: "")],
              isLoading: false,
              showError: false,
              errorMessage: ""
            )

          ExerciseCompletionComponent(
            exercise: exercise,
            viewModel: ExerciseCompletionViewModel(exerciseId: exercise.id),
            sets: Binding(
              get: { exerciseState.sets },
              set: { exerciseStates[exercise.id]?.sets = $0 }
            ),
            isLoading: Binding(
              get: { exerciseState.isLoading },
              set: { exerciseStates[exercise.id]?.isLoading = $0 }
            ),
            showError: Binding(
              get: { exerciseState.showError },
              set: { exerciseStates[exercise.id]?.showError = $0 }
            ),
            errorMessage: Binding(
              get: { exerciseState.errorMessage },
              set: { exerciseStates[exercise.id]?.errorMessage = $0 }
            ),
            onComplete: {
              // Check if all exercises are completed
              Task {
                await checkWorkoutCompletion()
              }
            }
          )
          .padding(.horizontal)
        }
      }
    }
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) {
        showError = false
      }
    } message: {
      Text(errorMessage)
    }
  }

  private func startWorkout() async {
    isLoading = true
    defer { isLoading = false }

    do {
      let db = Firestore.firestore()
      guard let userId = Auth.auth().currentUser?.uid else {
        errorMessage = "User not logged in"
        showError = true
        return
      }

      let workoutCompletion =
        [
          "workoutId": workout.id,
          "userId": userId,
          "exerciseCompletions": [],
          "startedAt": Timestamp(),
          "notes": "",
        ] as [String: Any]

      let docRef = try await db.collection("workoutCompletions").addDocument(
        data: workoutCompletion)
      workoutCompletionId = docRef.documentID
      startTime = Date()
      isStarted = true
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func cancelWorkout() async {
    isLoading = true
    defer { isLoading = false }

    do {
      if let workoutCompletionId = workoutCompletionId {
        let db = Firestore.firestore()
        try await db.collection("workoutCompletions").document(workoutCompletionId).delete()
        self.workoutCompletionId = nil
        isStarted = false
        startTime = nil
        onComplete?()
      }
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func checkWorkoutCompletion() async {
    // Get all exercise completions for this workout completion
    let db = Firestore.firestore()
    do {
      if let workoutCompletionId = workoutCompletionId {
        let snapshot = try await db.collection("exerciseCompletions")
          .whereField("workoutCompletionId", isEqualTo: workoutCompletionId)
          .getDocuments()

        let completedExercises = Set(
          snapshot.documents.map { $0.data()["exerciseId"] as? String ?? "" })
        let allExercises = Set(workout.exercises.map { $0.id })

        // If all exercises are completed, finish the workout
        if completedExercises == allExercises {
          try await db.collection("workoutCompletions").document(workoutCompletionId).updateData([
            "finishedAt": Timestamp()
          ])
          onComplete?()
        }
      }
    } catch {
      errorMessage = error.localizedDescription
      showError = true
    }
  }
}
