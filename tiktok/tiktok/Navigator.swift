import SwiftUI

enum Destination: Hashable, Identifiable {
    case videoDetail(workoutPlan: WorkoutPlan, workoutIndex: Int?, exerciseIndex: Int?)
    case exerciseCompletion(exercise: Exercise)
    case userProfile(userId: String)
    case profile
    case videoFeed(videos: [WorkoutPlan], startIndex: Int)
    case exercise(Exercise)
    case workout(Workout)
    case workoutPlan(WorkoutPlan)
    case profileVideo(workoutPlan: WorkoutPlan)

    var id: String {
        switch self {
        case let .videoDetail(workoutPlan, _, _):
            return "videoDetail-\(workoutPlan.id)"
        case let .exerciseCompletion(exercise):
            return "exerciseCompletion-\(exercise.id)"
        case let .userProfile(userId):
            return "userProfile-\(userId)"
        case .profile:
            return "profile"
        case let .videoFeed(videos, startIndex):
            return "videoFeed-\(videos.first?.id ?? "")-\(startIndex)"
        case let .exercise(exercise):
            return "exercise-\(exercise.id)"
        case let .workout(workout):
            return "workout-\(workout.id)"
        case let .workoutPlan(plan):
            return "workoutPlan-\(plan.id)"
        case let .profileVideo(workoutPlan):
            return "profileVideo-\(workoutPlan.id)"
        }
    }
}

@ViewBuilder
func view(for destination: Destination) -> some View {
    switch destination {
    case let .videoDetail(workoutPlan, workoutIndex, exerciseIndex):
        VideoDetailView(
            workoutPlan: workoutPlan, workoutIndex: workoutIndex, exerciseIndex: exerciseIndex
        )
    case let .exerciseCompletion(exercise):
        ExerciseCompletionView(exercise: exercise)
    case let .userProfile(userId):
        ProfileView(userId: userId)
    case .profile:
        ProfileView()
    case let .videoFeed(videos, startIndex):
        VideoFeedView(initialVideos: videos, startingAt: startIndex)
    case let .exercise(exercise):
        // Convert exercise to video detail
        let workoutPlan = WorkoutPlan(
            id: UUID().uuidString,
            title: exercise.title,
            description: exercise.description,
            instructorId: exercise.instructorId,
            videoUrl: exercise.videoUrl,
            thumbnailUrl: exercise.thumbnailUrl,
            difficulty: exercise.difficulty,
            targetMuscles: exercise.targetMuscles,
            workouts: [
                WorkoutWithMetadata(
                    workout: Workout(
                        id: UUID().uuidString,
                        title: exercise.title,
                        description: exercise.description,
                        exercises: [exercise],
                        instructorId: exercise.instructorId,
                        videoUrl: exercise.videoUrl,
                        thumbnailUrl: exercise.thumbnailUrl,
                        difficulty: exercise.difficulty,
                        targetMuscles: exercise.targetMuscles,
                        totalDuration: exercise.duration,
                        createdAt: exercise.createdAt,
                        updatedAt: exercise.updatedAt
                    ),
                    weekNumber: 1,
                    dayOfWeek: 1
                )
            ],
            duration: 1,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt
        )
        VideoDetailView(workoutPlan: workoutPlan, workoutIndex: 0, exerciseIndex: 0)
    case let .workout(workout):
        // Convert workout to video detail
        let workoutPlan = WorkoutPlan(
            id: UUID().uuidString,
            title: workout.title,
            description: workout.description,
            instructorId: workout.instructorId,
            videoUrl: workout.videoUrl,
            thumbnailUrl: workout.thumbnailUrl,
            difficulty: workout.difficulty,
            targetMuscles: workout.targetMuscles,
            workouts: [WorkoutWithMetadata(workout: workout, weekNumber: 1, dayOfWeek: 1)],
            duration: 1,
            createdAt: workout.createdAt,
            updatedAt: workout.updatedAt
        )
        VideoDetailView(workoutPlan: workoutPlan, workoutIndex: 0, exerciseIndex: nil)
    case let .workoutPlan(plan):
        VideoDetailView(workoutPlan: plan, workoutIndex: nil, exerciseIndex: nil)
    case let .profileVideo(workoutPlan):
        ProfileVideoWrapper(workoutPlan: workoutPlan)
    }
}

final class Navigator: ObservableObject {
    @Published var path = NavigationPath()
    @Published var presentedSheet: Destination?

    private func logNavigation(_ message: String) {
        print("🎬 Navigator: \(message)")
    }

    func navigate(to destination: Destination) {
        logNavigation("Navigating to \(destination.id)")

        switch destination {
        case .videoDetail, .videoFeed, .profile, .userProfile,
             .exercise, .workout, .workoutPlan, .profileVideo:
            path.append(destination)
        case .exerciseCompletion:
            presentedSheet = destination
        }
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
