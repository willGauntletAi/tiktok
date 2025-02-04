import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct CreateWorkoutView: View {
  @StateObject private var viewModel = CreateWorkoutViewModel()
  @FocusState private var focusedField: Field?
  @Environment(\.presentationMode) var presentationMode

  enum Field {
    case title
    case description
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        VideoSelectionView(
          videoThumbnail: $viewModel.videoThumbnail,
          showCamera: $viewModel.showCamera,
          onVideoSelected: { item in
            await viewModel.loadVideo(from: item)
          }
        )

        // Basic Info
        GroupBox(label: Text("Workout Details").bold()) {
          VStack(spacing: 12) {
            TextField("Title", text: $viewModel.workout.title)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .focused($focusedField, equals: .title)

            TextField("Description", text: $viewModel.workout.description, axis: .vertical)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .lineLimit(3...6)
              .focused($focusedField, equals: .description)

            Picker("Difficulty", selection: $viewModel.workout.difficulty) {
              ForEach(Difficulty.allCases, id: \.self) { difficulty in
                Text(difficulty.rawValue.capitalized)
              }
            }
          }
        }
        .padding(.horizontal)

        // Target Muscles
        GroupBox(label: Text("Target Muscles").bold()) {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(MuscleGroups.all, id: \.self) { muscle in
                FilterChip(
                  title: muscle,
                  isSelected: viewModel.workout.targetMuscles.contains(muscle)
                ) {
                  if viewModel.workout.targetMuscles.contains(muscle) {
                    viewModel.workout.targetMuscles.removeAll { $0 == muscle }
                  } else {
                    viewModel.workout.targetMuscles.append(muscle)
                  }
                }
              }
            }
            .padding(.horizontal)
          }
        }
        .padding(.horizontal)

        // Exercises
        GroupBox {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Exercises").bold()
              Spacer()
              Button(action: { viewModel.showExerciseSelector = true }) {
                Label("Add Exercise", systemImage: "plus.circle.fill")
              }
            }

            if viewModel.selectedExercises.isEmpty {
              Text("No exercises added")
                .foregroundColor(.gray)
                .padding(.vertical)
            } else {
              List {
                ForEach(viewModel.selectedExercises) { exercise in
                  HStack {
                    VStack(alignment: .leading) {
                      Text(exercise.title)
                        .font(.headline)
                      Text("\(exercise.duration) seconds")
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                      .foregroundColor(.gray)
                  }
                  .contentShape(Rectangle())
                }
                .onMove { source, destination in
                  viewModel.moveExercise(from: source, to: destination)
                }
                .onDelete { offsets in
                  viewModel.removeExercise(at: offsets)
                }
              }
              .frame(height: CGFloat(viewModel.selectedExercises.count * 60))
              .listStyle(PlainListStyle())

              Text("Total Duration: \(viewModel.workout.totalDuration) seconds")
                .font(.caption)
                .foregroundColor(.gray)
            }
          }
        }
        .padding(.horizontal)

        // Save Button
        Button(action: {
          Task {
            await viewModel.saveWorkout()
          }
        }) {
          if viewModel.isLoading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Text("Save Workout")
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(viewModel.canSave ? Color.blue : Color.gray)
        .foregroundColor(.white)
        .cornerRadius(10)
        .disabled(!viewModel.canSave || viewModel.isLoading)
        .padding(.horizontal)
      }
      .padding(.vertical)
    }
    .background(
      Color(.systemBackground)
        .onTapGesture {
          focusedField = nil
        }
    )
    .navigationTitle("Create Workout")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $viewModel.showExerciseSelector) {
      NavigationView {
        FindExerciseView(
          onExerciseSelected: { exercise in
            if viewModel.selectedExercises.contains(where: { $0.id == exercise.id }) {
              viewModel.removeExercise(exercise)
            } else {
              viewModel.addExercise(exercise)
            }
          },
          selectedExerciseIds: Set(viewModel.selectedExercises.map { $0.id })
        )
      }
    }
    .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
      Button("OK", role: .cancel) {
        viewModel.errorMessage = nil
      }
    } message: {
      if let error = viewModel.errorMessage {
        Text(error)
      }
    }
    .onChange(of: viewModel.shouldNavigateToProfile) { shouldNavigate in
      if shouldNavigate {
        presentationMode.wrappedValue.dismiss()
      }
    }
  }
}

// Helper struct for muscle groups
enum MuscleGroups {
  static let all = [
    "Chest", "Back", "Shoulders", "Biceps", "Triceps",
    "Legs", "Core", "Full Body",
  ]
}
