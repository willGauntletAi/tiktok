import SwiftUI

struct CreateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: NavigationPath = .init()

    var body: some View {
        NavigationStack(path: $selectedPath) {
            VStack(spacing: 24) {
                Text("What would you like to create?")
                    .font(.title2)
                    .padding(.top)

                Button {
                    selectedPath.append("exercise")
                } label: {
                    CreateOptionCard(
                        title: "Exercise",
                        description: "Create a single exercise with video instructions",
                        systemImage: "figure.run",
                        color: .blue
                    )
                }

                Button {
                    selectedPath.append("workout")
                } label: {
                    CreateOptionCard(
                        title: "Workout",
                        description: "Combine multiple exercises into a workout",
                        systemImage: "figure.strengthtraining.traditional",
                        color: .purple
                    )
                }

                Button {
                    selectedPath.append("workoutPlan")
                } label: {
                    CreateOptionCard(
                        title: "Workout Plan",
                        description: "Create a multi-day workout program",
                        systemImage: "calendar.badge.clock",
                        color: .orange
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { destination in
                switch destination {
                case "exercise":
                    CreateExerciseView(onComplete: {
                        selectedPath = NavigationPath()
                        dismiss()
                    })
                case "workout":
                    CreateWorkoutView(onComplete: {
                        selectedPath = NavigationPath()
                        dismiss()
                    })
                case "workoutPlan":
                    CreateWorkoutPlanView(onComplete: {
                        selectedPath = NavigationPath()
                        dismiss()
                    })
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct CreateOptionCard: View {
    let title: String
    let description: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
