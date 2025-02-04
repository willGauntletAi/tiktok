import SwiftUI

struct SearchView: View {
  @StateObject private var viewModel = SearchViewModel()

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        // Muscle Groups Filter
        VStack(alignment: .leading, spacing: 4) {
          Text("Target Muscles")
            .font(.headline)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(viewModel.muscleGroups, id: \.self) { muscle in
                FilterChip(
                  title: muscle,
                  isSelected: viewModel.selectedMuscles.contains(muscle)
                ) {
                  viewModel.toggleMuscle(muscle)
                }
              }
            }
            .padding(.horizontal)
          }
        }

        // Difficulty Filter
        VStack(alignment: .leading, spacing: 4) {
          Text("Difficulty")
            .font(.headline)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              FilterChip(
                title: "All",
                isSelected: viewModel.selectedDifficulty == nil
              ) {
                viewModel.setDifficulty(nil)
              }

              ForEach(viewModel.difficultyLevels, id: \.self) { difficulty in
                FilterChip(
                  title: difficulty.capitalized,
                  isSelected: viewModel.selectedDifficulty == difficulty
                ) {
                  viewModel.setDifficulty(difficulty)
                }
              }
            }
            .padding(.horizontal)
          }
        }

        // Results
        LazyVStack(spacing: 15) {
          ForEach(viewModel.exercises) { exercise in
            ExerciseCard(exercise: exercise)
              .padding(.horizontal)
          }
        }
      }
      .padding(.horizontal)
      .navigationTitle("Search Exercises")
      .navigationBarTitleDisplayMode(.inline)
    }
    .task {
      await viewModel.searchExercises()
    }
  }
}

struct FilterChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
        .foregroundColor(isSelected ? .white : .primary)
        .cornerRadius(20)
    }
  }
}

struct ExerciseCard: View {
  let exercise: Exercise

  var body: some View {
    NavigationLink(destination: VideoDetailView(item: exercise, type: "exercise")) {
      VStack(alignment: .leading) {
        let thumbnailUrl = exercise.thumbnailUrl
        AsyncImage(url: URL(string: thumbnailUrl)) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          Rectangle()
            .fill(Color.gray.opacity(0.2))
        }
        .frame(height: 200)
        .cornerRadius(10)

        VStack(alignment: .leading, spacing: 4) {
          Text(exercise.title)
            .font(.headline)

          Text(exercise.description)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(2)

          HStack {
            Text(exercise.difficulty.rawValue.capitalized)
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.blue.opacity(0.2))
              .cornerRadius(8)

            ForEach(exercise.targetMuscles, id: \.self) { muscle in
              Text(muscle)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
          }
        }
        .padding(.vertical, 8)
      }
      .background(Color(.systemBackground))
      .cornerRadius(12)
      .shadow(radius: 2)
    }
  }
}
