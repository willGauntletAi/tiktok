import AVKit
import SwiftUI
import UIKit

struct VideoDetailView: View {
    let workoutPlan: WorkoutPlan
    let workoutIndex: Int?
    let exerciseIndex: Int?
    @StateObject private var viewModel: VideoDetailViewModel
    @State private var player: AVPlayer?
    @State private var isExpanded = false
    @State private var firstLineDescription: String = ""
    @State private var fullDescription: String = ""
    @State private var showComments = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: Navigator

    init(
        workoutPlan: WorkoutPlan, workoutIndex: Int? = nil, exerciseIndex: Int? = nil
    ) {
        self.workoutPlan = workoutPlan
        self.workoutIndex = workoutIndex
        self.exerciseIndex = exerciseIndex

        let videoId: String
        if let exerciseIndex = exerciseIndex,
           let workoutIndex = workoutIndex
        {
            videoId = workoutPlan.workouts[workoutIndex].workout.exercises[exerciseIndex].id
        } else if let workoutIndex = workoutIndex {
            videoId = workoutPlan.workouts[workoutIndex].workout.id
        } else {
            videoId = workoutPlan.id
        }
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(videoId: videoId))
    }

    private var currentWorkout: Workout? {
        guard let workoutIndex = workoutIndex else { return nil }
        return workoutPlan.workouts[workoutIndex].workout
    }

    private var currentWorkoutMetadata: WorkoutWithMetadata? {
        guard let workoutIndex = workoutIndex else { return nil }
        return workoutPlan.workouts[workoutIndex]
    }

    private var currentExercise: Exercise? {
        guard let workoutIndex = workoutIndex,
              let exerciseIndex = exerciseIndex
        else { return nil }
        return workoutPlan.workouts[workoutIndex].workout.exercises[exerciseIndex]
    }

    private var title: String {
        if let exercise = currentExercise {
            return exercise.title
        } else if let workout = currentWorkout {
            return workout.title
        } else {
            return workoutPlan.title
        }
    }

    private var description: String {
        if let exercise = currentExercise {
            return exercise.description
        } else if let workout = currentWorkout {
            return workout.description
        } else {
            return workoutPlan.description
        }
    }

    private var videoUrl: String {
        if let exercise = currentExercise {
            return exercise.videoUrl
        } else if let workout = currentWorkout {
            return workout.videoUrl
        } else {
            return workoutPlan.videoUrl
        }
    }

    private var difficulty: Difficulty {
        if let exercise = currentExercise {
            return exercise.difficulty
        } else if let workout = currentWorkout {
            return workout.difficulty
        } else {
            return workoutPlan.difficulty
        }
    }

    private var targetMuscles: [String] {
        if let exercise = currentExercise {
            return exercise.targetMuscles
        } else if let workout = currentWorkout {
            return workout.targetMuscles
        } else {
            return workoutPlan.targetMuscles
        }
    }

    private var instructorId: String {
        if let exercise = currentExercise {
            return exercise.instructorId
        } else if let workout = currentWorkout {
            return workout.instructorId
        } else {
            return workoutPlan.instructorId
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                // Video Player
                if let videoUrl = URL(string: videoUrl) {
                    VStack {
                        Spacer()
                        VideoPlayer(player: player ?? AVPlayer())
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .aspectRatio(contentMode: .fit)
                            .onAppear {
                                player = AVPlayer(url: videoUrl)
                                player?.play()
                            }
                            .onDisappear {
                                player?.pause()
                                player = nil
                            }
                        Spacer()
                    }
                    .edgesIgnoringSafeArea(.all)
                }

                // Right side buttons
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        // Like Button
                        Button(action: {
                            Task {
                                await viewModel.toggleLike()
                            }
                        }) {
                            Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 28))
                                .foregroundColor(viewModel.isLiked ? .red : .white)
                                .shadow(radius: 2)
                        }
                        .disabled(viewModel.isLoading)
                        .accessibilityLabel("Like Video")
                        .accessibilityAddTraits(viewModel.isLiked ? .isSelected : [])
                        .overlay {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }

                        // Profile Button
                        Button(action: {
                            navigator.navigate(to: .userProfile(userId: instructorId))
                        }) {
                            VStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)

                                Text("@\(viewModel.instructorName)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityLabel("View Profile")
                        .accessibilityValue("@\(viewModel.instructorName)")

                        // Comment Button
                        Button(action: {
                            showComments = true
                        }) {
                            VStack {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)

                                Text("Comments")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityLabel("View Comments")

                        // Exercise Completion Button (only show for exercises)
                        if let exercise = currentExercise {
                            Button(action: {
                                navigator.navigate(to: .exerciseCompletion(exercise: exercise))
                            }) {
                                VStack {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)

                                    Text("Complete")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .lineLimit(1)
                                }
                            }
                            .accessibilityLabel("Record Exercise Completion")
                        }
                    }
                    .frame(width: 80)
                    .padding(.trailing, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Content Overlay
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        // Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }

                        // Description
                        Text(isExpanded ? fullDescription : firstLineDescription)
                            .font(.body)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                            .lineLimit(isExpanded ? nil : 1)

                        if isExpanded {
                            // Additional details
                            VStack(alignment: .leading, spacing: 12) {
                                DetailRow(
                                    title: "Difficulty",
                                    value: difficulty.rawValue.capitalized
                                )
                                DetailRow(
                                    title: "Target Muscles",
                                    value: targetMuscles.joined(separator: ", ")
                                )
                                if let exercise = currentExercise {
                                    DetailRow(title: "Duration", value: "\(exercise.duration) seconds")
                                } else if let workoutMeta = currentWorkoutMetadata {
                                    DetailRow(
                                        title: "Total Duration",
                                        value: "\(workoutMeta.workout.totalDuration) seconds"
                                    )
                                    DetailRow(
                                        title: "Exercises",
                                        value: "\(workoutMeta.workout.exercises.count)"
                                    )
                                    DetailRow(
                                        title: "Schedule",
                                        value: "Week \(workoutMeta.weekNumber), Day \(workoutMeta.dayOfWeek)"
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(
                                colors: [.black.opacity(0.7), .black.opacity(0.4), .clear]
                            ),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isExpanded ? .infinity : geometry.size.width * 0.8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            isExpanded.toggle()
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            fullDescription = description
            if let firstLine = description.components(separatedBy: .newlines).first {
                firstLineDescription = firstLine
            } else {
                firstLineDescription = description
            }
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .sheet(isPresented: $showComments) {
            CommentSheetView(viewModel: CommentViewModel(videoId: viewModel.videoId))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .shadow(radius: 2)

            Text(value)
                .font(.body)
                .foregroundColor(.white)
                .shadow(radius: 2)
        }
    }
}
