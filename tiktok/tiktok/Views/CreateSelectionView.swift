import SwiftUI

struct CreateSelectionView: View {
  var body: some View {
    NavigationView {
      VStack(spacing: 24) {
        Text("What would you like to create?")
          .font(.title2)
          .padding(.top)

        NavigationLink(destination: CreateExerciseView()) {
          CreateOptionCard(
            title: "Exercise",
            description: "Create a single exercise with video instructions",
            systemImage: "figure.run",
            color: .blue
          )
        }

        NavigationLink(destination: CreateWorkoutView()) {
          CreateOptionCard(
            title: "Workout",
            description: "Combine multiple exercises into a workout",
            systemImage: "figure.strengthtraining.traditional",
            color: .purple
          )
        }

        Spacer()
      }
      .padding()
      .navigationTitle("Create")
      .navigationBarTitleDisplayMode(.inline)
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
