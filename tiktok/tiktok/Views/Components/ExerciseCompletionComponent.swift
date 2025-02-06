import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import SwiftUI

struct ExerciseCompletionComponent: View {
    let exercise: Exercise
    let viewModel: ExerciseCompletionViewModel
    @Binding var sets: [ExerciseSet]
    @Binding var isLoading: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // Exercise Info
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercise Details")
                        .font(.headline)
                        .bold()

                    Text(exercise.title)
                        .font(.headline)

                    Text(exercise.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let targetSets = exercise.sets {
                        HStack {
                            Image(systemName: "number.square")
                            Text("\(targetSets) sets recommended")
                        }
                        .foregroundColor(.secondary)
                    }

                    if let targetReps = exercise.reps {
                        HStack {
                            Image(systemName: "repeat")
                            Text("\(targetReps) reps recommended")
                        }
                        .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Muscles")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TagsView(tags: exercise.targetMuscles)
                    }
                }
            }
            .padding(.horizontal)

            // History Section
            GroupBox {
                DisclosureGroup {
                    if viewModel.isLoadingHistory {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.recentCompletions.isEmpty {
                        Text("No previous completions")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        VStack(spacing: 16) {
                            ForEach(viewModel.recentCompletions) { completion in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(completion.completedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }

                                    HStack(spacing: 16) {
                                        Label("\(completion.repsCompleted) reps", systemImage: "repeat")

                                        if let weight = completion.weight {
                                            Label(String(format: "%.1f lbs", weight), systemImage: "scalemass")
                                        }
                                    }
                                    .foregroundColor(.primary)

                                    if !completion.notes.isEmpty {
                                        Text(completion.notes)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }

                            if viewModel.hasMoreHistory {
                                Button(action: {
                                    Task {
                                        await viewModel.fetchMoreHistory()
                                    }
                                }) {
                                    Text("Show More")
                                        .foregroundColor(.blue)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                } label: {
                    Label("Recent History", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal)
            .task {
                await viewModel.fetchRecentCompletions()
            }

            // Sets
            GroupBox(label: Text("Sets").bold()) {
                VStack(spacing: 16) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, _ in
                        VStack(spacing: 12) {
                            Text("Set \(index + 1)")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Text("Reps")
                                Spacer()
                                TextField("Required", value: $sets[index].reps, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            HStack {
                                Text("Weight (lbs)")
                                Spacer()
                                TextField("Optional", value: $sets[index].weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 100)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            TextField("Notes (optional)", text: $sets[index].notes)
                                .textFieldStyle(RoundedBorderTextFieldStyle())

                            if sets.count > 1 {
                                Button(
                                    role: .destructive,
                                    action: {
                                        sets.remove(at: index)
                                    }
                                ) {
                                    Label("Remove Set", systemImage: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    Button(action: {
                        sets.append(ExerciseSet(reps: 0, weight: nil, notes: ""))
                    }) {
                        Label("Add Set", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
