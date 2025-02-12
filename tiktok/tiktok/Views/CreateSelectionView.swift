import SwiftUI

struct CreateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        VStack(spacing: 24) {
            Text("What would you like to create?")
                .font(.title2)
                .padding(.top)

            Button {
                navigator.navigate(to: .createExercise)
            } label: {
                CreateOptionCard(
                    title: "Exercise",
                    description: "Create a single exercise with video instructions",
                    systemImage: "figure.run",
                    color: .blue
                )
            }

            Button {
                navigator.navigate(to: .createWorkout)
            } label: {
                CreateOptionCard(
                    title: "Workout",
                    description: "Combine multiple exercises into a workout",
                    systemImage: "figure.strengthtraining.traditional",
                    color: .purple
                )
            }

            Button {
                navigator.navigate(to: .createWorkoutPlan)
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
