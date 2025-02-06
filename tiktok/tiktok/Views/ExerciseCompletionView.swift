import FirebaseAuth
import FirebaseFirestore
import SwiftUI

struct ExerciseCompletionView: View {
    let exercise: Exercise
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel: ExerciseCompletionViewModel
    @State private var sets: [ExerciseSet] = [ExerciseSet(reps: 0, weight: nil, notes: "")]
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    init(exercise: Exercise) {
        self.exercise = exercise
        _viewModel = StateObject(
            wrappedValue: ExerciseCompletionViewModel(exerciseId: exercise.id))
    }

    var body: some View {
        VStack {
            ScrollView {
                ExerciseCompletionComponent(
                    exercise: exercise,
                    viewModel: viewModel,
                    sets: $sets,
                    isLoading: $isLoading,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    onComplete: {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
                .padding(.vertical)
            }

            // Save Button
            Button(action: {
                Task {
                    await saveCompletions()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Save Sets")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(sets.allSatisfy { $0.reps > 0 } ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(!sets.allSatisfy { $0.reps > 0 } || isLoading)
            .padding(.horizontal)
        }
        .navigationTitle("Record Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func saveCompletions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let db = Firestore.firestore()
            guard let userId = Auth.auth().currentUser?.uid else {
                errorMessage = "User not logged in"
                showError = true
                return
            }

            // Create exercise completions for each set
            for set in sets {
                let completion =
                    [
                        "exerciseId": exercise.id,
                        "userId": userId,
                        "repsCompleted": set.reps,
                        "weight": set.weight as Any,
                        "notes": set.notes,
                        "completedAt": Timestamp(),
                    ] as [String: Any]

                try await db.collection("exerciseCompletions").addDocument(data: completion)
            }

            presentationMode.wrappedValue.dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
