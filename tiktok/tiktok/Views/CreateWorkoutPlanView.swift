import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct CreateWorkoutPlanView: View {
  @StateObject private var viewModel = CreateWorkoutPlanViewModel()
  @FocusState private var focusedField: Field?
  @Environment(\.presentationMode) var presentationMode

  enum Field {
    case title
    case description
  }

  var body: some View {
    NavigationStack {
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
          GroupBox(label: Text("Workout Plan Details").bold()) {
            VStack(spacing: 12) {
              TextField("Title", text: $viewModel.workoutPlan.title)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .title)

              TextField("Description", text: $viewModel.workoutPlan.description, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
                .focused($focusedField, equals: .description)

              Picker("Difficulty", selection: $viewModel.workoutPlan.difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                  Text(difficulty.rawValue.capitalized)
                }
              }

              Stepper(
                "Duration: \(viewModel.workoutPlan.duration) days",
                value: $viewModel.workoutPlan.duration,
                in: 1...90
              )
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
                    isSelected: viewModel.workoutPlan.targetMuscles.contains(muscle)
                  ) {
                    if viewModel.workoutPlan.targetMuscles.contains(muscle) {
                      viewModel.workoutPlan.targetMuscles.removeAll { $0 == muscle }
                    } else {
                      viewModel.workoutPlan.targetMuscles.append(muscle)
                    }
                  }
                }
              }
            }
            .padding(.horizontal)
          }
          .padding(.horizontal)

          // Workouts
          GroupBox {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("Workouts").bold()
                Spacer()
                Button(action: { viewModel.showWorkoutSelector = true }) {
                  Label("Add Workout", systemImage: "plus.circle.fill")
                }
              }

              if viewModel.selectedWorkouts.isEmpty {
                Text("No workouts added")
                  .foregroundColor(.gray)
                  .padding(.vertical)
              } else {
                List {
                  ForEach(viewModel.selectedWorkouts) { workout in
                    HStack {
                      VStack(alignment: .leading) {
                        Text(workout.title)
                          .font(.headline)
                        Text("\(workout.totalDuration) seconds")
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
                    viewModel.moveWorkout(from: source, to: destination)
                  }
                  .onDelete { offsets in
                    viewModel.removeWorkout(at: offsets)
                  }
                }
                .frame(height: CGFloat(viewModel.selectedWorkouts.count * 60))
                .listStyle(PlainListStyle())
              }
            }
          }
          .padding(.horizontal)

          // Save Button
          Button(action: {
            Task {
              await viewModel.saveWorkoutPlan()
            }
          }) {
            if viewModel.isLoading {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
              Text("Save Workout Plan")
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
      .navigationTitle("Create Workout Plan")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $viewModel.showWorkoutSelector) {
        NavigationStack {
          FindVideoView<Workout>(
            type: "Workout",
            title: "Select Workouts",
            onItemSelected: { workout in
              if viewModel.selectedWorkouts.contains(where: { $0.id == workout.id }) {
                viewModel.removeWorkout(workout)
              } else {
                viewModel.addWorkout(workout)
              }
            },
            selectedIds: Set(viewModel.selectedWorkouts.map { String(describing: $0.id) })
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
}
