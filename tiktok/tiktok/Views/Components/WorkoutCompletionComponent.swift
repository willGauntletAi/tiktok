import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import SwiftUI

struct WorkoutCompletionComponent: View {
    let workout: Workout
    @ObservedObject var viewModel: WorkoutCompletionViewModel
    var onComplete: (() -> Void)?

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
            if !viewModel.isStarted {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.startWorkout()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            viewModel.showError = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
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
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.cancelWorkout()
                            onComplete?()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                            viewModel.showError = true
                        }
                    }
                }) {
                    if viewModel.isLoading {
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
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
            }

            if viewModel.isStarted {
                // Exercise List
                ForEach(workout.exercises, id: \.id) { exercise in
                    let exerciseState =
                        viewModel.exerciseStates[exercise.id]
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
                            set: { viewModel.exerciseStates[exercise.id]?.sets = $0 }
                        ),
                        isLoading: Binding(
                            get: { exerciseState.isLoading },
                            set: { viewModel.exerciseStates[exercise.id]?.isLoading = $0 }
                        ),
                        showError: Binding(
                            get: { exerciseState.showError },
                            set: { viewModel.exerciseStates[exercise.id]?.showError = $0 }
                        ),
                        errorMessage: Binding(
                            get: { exerciseState.errorMessage },
                            set: { viewModel.exerciseStates[exercise.id]?.errorMessage = $0 }
                        ),
                        onComplete: {
                            // Check if all exercises are completed
                            Task {
                                do {
                                    try await viewModel.checkWorkoutCompletion()
                                    onComplete?()
                                } catch {
                                    viewModel.errorMessage = error.localizedDescription
                                    viewModel.showError = true
                                }
                            }
                        }
                    )
                    .padding(.horizontal)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
