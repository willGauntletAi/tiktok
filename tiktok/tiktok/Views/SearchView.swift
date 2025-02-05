import SwiftUI

struct SearchView: View {
  @StateObject private var viewModel = SearchViewModel()
  @State private var selectedItem: (any Identifiable, String)?
  @State private var searchText = ""

  var body: some View {
    VStack(spacing: 0) {
      // Filters Section
      VStack(spacing: 16) {
        // Content Type Picker
        Picker("Content Type", selection: $viewModel.selectedContentType) {
          ForEach(ContentType.allCases, id: \.self) { type in
            Text(type.displayName).tag(type)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: viewModel.selectedContentType) { _ in
          Task {
            await viewModel.search()
          }
        }

        // Search Bar
        TextField("Search", text: $viewModel.searchText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .padding(.horizontal)

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
                  title: difficulty.rawValue.capitalized,
                  isSelected: viewModel.selectedDifficulty == difficulty
                ) {
                  viewModel.setDifficulty(difficulty)
                }
              }
            }
            .padding(.horizontal)
          }
        }
      }
      .padding(.vertical)

      // Results Section
      ScrollView {
        LazyVStack(spacing: 15) {
          ForEach(viewModel.exercises) { exercise in
            NavigationLink(value: SearchDestination.exercise(exercise)) {
              ContentCard(
                title: exercise.title,
                description: exercise.description,
                thumbnailUrl: exercise.thumbnailUrl,
                difficulty: exercise.difficulty.rawValue,
                targetMuscles: exercise.targetMuscles,
                contentType: .exercise
              )
            }
            .buttonStyle(PlainButtonStyle())
          }

          ForEach(viewModel.workouts) { workout in
            NavigationLink(value: SearchDestination.workout(workout)) {
              ContentCard(
                title: workout.title,
                description: workout.description,
                thumbnailUrl: workout.thumbnailUrl,
                difficulty: workout.difficulty.rawValue,
                targetMuscles: workout.targetMuscles,
                contentType: .workout
              )
            }
            .buttonStyle(PlainButtonStyle())
          }

          ForEach(viewModel.workoutPlans) { plan in
            NavigationLink(value: SearchDestination.workoutPlan(plan)) {
              ContentCard(
                title: plan.title,
                description: plan.description,
                thumbnailUrl: plan.thumbnailUrl,
                difficulty: plan.difficulty.rawValue,
                targetMuscles: plan.targetMuscles,
                contentType: .workoutPlan
              )
            }
            .buttonStyle(PlainButtonStyle())
          }
        }
        .padding(.horizontal)
      }
    }
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: viewModel.searchText) { _ in
      Task {
        await viewModel.search()
      }
    }
    .task {
      await viewModel.search()
    }
    .navigationDestination(for: SearchDestination.self) { destination in
      switch destination {
      case .exercise(let exercise):
        VideoDetailView(item: exercise, type: "exercise")
      case .workout(let workout):
        VideoDetailView(item: workout, type: "workout")
      case .workoutPlan(let plan):
        VideoDetailView(item: plan, type: "workoutPlan")
      }
    }
  }
}

struct ContentCard: View {
  let title: String
  let description: String
  let thumbnailUrl: String
  let difficulty: String
  let targetMuscles: [String]
  let contentType: ContentType

  var body: some View {
    VStack(alignment: .leading) {
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
        HStack {
          Text(title)
            .font(.headline)
          Spacer()
          Text(contentType.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
        }

        Text(description)
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(2)

        HStack {
          Text(difficulty.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)

          ForEach(targetMuscles.prefix(3), id: \.self) { muscle in
            Text(muscle)
              .font(.caption)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color.green.opacity(0.2))
              .cornerRadius(8)
          }

          if targetMuscles.count > 3 {
            Text("+\(targetMuscles.count - 3)")
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
    .buttonStyle(FilterChipButtonStyle())
  }
}

struct FilterChipButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .allowsHitTesting(true)
  }
}

enum SearchDestination: Hashable {
  case exercise(Exercise)
  case workout(Workout)
  case workoutPlan(WorkoutPlan)

  func hash(into hasher: inout Hasher) {
    switch self {
    case .exercise(let exercise):
      hasher.combine("exercise")
      hasher.combine(exercise.id)
    case .workout(let workout):
      hasher.combine("workout")
      hasher.combine(workout.id)
    case .workoutPlan(let plan):
      hasher.combine("workoutPlan")
      hasher.combine(plan.id)
    }
  }

  static func == (lhs: SearchDestination, rhs: SearchDestination) -> Bool {
    switch (lhs, rhs) {
    case (.exercise(let e1), .exercise(let e2)):
      return e1.id == e2.id
    case (.workout(let w1), .workout(let w2)):
      return w1.id == w2.id
    case (.workoutPlan(let p1), .workoutPlan(let p2)):
      return p1.id == p2.id
    default:
      return false
    }
  }
}
