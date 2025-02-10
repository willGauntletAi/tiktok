import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct CreateWorkoutPlanView: View {
    @StateObject private var viewModel = CreateWorkoutPlanViewModel()
    @FocusState private var focusedField: Field?
    @Environment(\.presentationMode) var presentationMode
    @State private var showVideoEditor = false
    @EnvironmentObject private var navigator: Navigator
    let onComplete: () -> Void

    enum Field {
        case title
        case description
    }

    private func videoSelectionSection() -> some View {
        GroupBox(label: Text("Video").bold()) {
            VStack {
                if viewModel.isUploading {
                    ProgressView("Uploading video...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if let thumbnail = viewModel.videoThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                } else {
                    Button(action: { showVideoEditor = true }) {
                        VStack {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 40))
                            Text("Add Video")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }

                if viewModel.videoThumbnail != nil {
                    Button(action: { showVideoEditor = true }) {
                        Text("Change Video")
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal)
    }

    private func workoutDetailsSection() -> some View {
        GroupBox(label: Text("Workout Plan Details").bold()) {
            VStack(spacing: 12) {
                TextField("Title", text: $viewModel.workoutPlan.title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .title)

                TextField("Description", text: $viewModel.workoutPlan.description, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3 ... 6)
                    .focused($focusedField, equals: .description)

                Picker("Difficulty", selection: $viewModel.workoutPlan.difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { difficulty in
                        Text(difficulty.rawValue.capitalized)
                    }
                }

                Stepper(
                    "Duration: \(viewModel.workoutPlan.duration) days",
                    value: $viewModel.workoutPlan.duration,
                    in: 1 ... 90
                )
            }
        }
        .padding(.horizontal)
    }

    private func targetMusclesSection() -> some View {
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
    }

    private func workoutsSection() -> some View {
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
                    let groupedWorkouts = Dictionary(grouping: viewModel.selectedWorkouts) {
                        $0.workoutWithMeta.weekNumber
                    }
                    VStack(spacing: 16) {
                        ForEach(groupedWorkouts.keys.sorted(), id: \.self) { week in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Week \(week)")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(
                                    groupedWorkouts[week]?.sorted(by: {
                                        $0.workoutWithMeta.dayOfWeek < $1.workoutWithMeta.dayOfWeek
                                    }) ?? []
                                ) { workoutInstance in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(workoutInstance.workoutWithMeta.workout.title)
                                                .font(.headline)
                                            HStack {
                                                Button(action: {
                                                    viewModel.editWorkoutSchedule(workoutInstance.id)
                                                }) {
                                                    let dayName = [
                                                        "", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
                                                        "Sunday",
                                                    ][workoutInstance.workoutWithMeta.dayOfWeek]
                                                    Text(dayName)
                                                        .font(.caption)
                                                        .foregroundColor(.blue)
                                                }
                                                Text("•")
                                                    .foregroundColor(.gray)
                                                Text("\(workoutInstance.workoutWithMeta.workout.totalDuration) seconds")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        Spacer()
                                        Button(action: {
                                            if let index = viewModel.selectedWorkouts.firstIndex(where: { $0.id == workoutInstance.id }) {
                                                viewModel.removeWorkout(at: IndexSet(integer: index))
                                            }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal)
    }

    private func saveButton() -> some View {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                videoSelectionSection()
                workoutDetailsSection()
                targetMusclesSection()
                workoutsSection()
                saveButton()
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
        .onAppear {
            viewModel.navigator = navigator
            viewModel.dismiss = onComplete
        }
        .sheet(isPresented: $showVideoEditor) {
            VideoEditView { url in
                Task {
                    let data = try? Data(contentsOf: url)
                    if let data = data {
                        await viewModel.processVideoData(data)
                    }
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        .sheet(isPresented: $viewModel.showWorkoutSelector) {
            NavigationStack {
                FindVideoView<Workout>(
                    type: "Workout",
                    title: "Select Workouts",
                    onItemSelected: { workout in
                        viewModel.addWorkout(workout)
                    },
                    selectedIds: Set(viewModel.selectedWorkouts.map { $0.workoutWithMeta.workout.id }),
                    actionButtonTitle: { id in
                        viewModel.selectedWorkouts.contains { $0.workoutWithMeta.workout.id == id }
                            ? "Add Again" : "Add"
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.showScheduleEditor) {
            if let workoutId = viewModel.editingWorkoutId,
               let workoutInstance = viewModel.selectedWorkouts.first(where: { $0.id == workoutId })
            {
                WorkoutScheduleDialog(
                    workout: workoutInstance.workoutWithMeta.workout,
                    initialWeek: workoutInstance.workoutWithMeta.weekNumber,
                    initialDay: workoutInstance.workoutWithMeta.dayOfWeek,
                    isPresented: $viewModel.showScheduleEditor,
                    onSchedule: { weekNumber, dayOfWeek in
                        viewModel.updateWorkoutSchedule(
                            workoutId: workoutId,
                            weekNumber: weekNumber,
                            dayOfWeek: dayOfWeek
                        )
                    }
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
    }
}
