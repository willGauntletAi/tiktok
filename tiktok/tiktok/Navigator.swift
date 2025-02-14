import SwiftUI

enum Destination: Hashable, Identifiable {
    case videoDetail(videos: [any VideoContent], startIndex: Int)
    case exerciseCompletion(exercise: Exercise)
    case userProfile(userId: String)
    case profile
    case videoFeed(videos: [[any VideoContent]], startIndex: Int)
    case exercise(Exercise)
    case workout(Workout)
    case workoutPlan(WorkoutPlan)
    case profileVideo(workoutPlan: WorkoutPlan)
    case createExercise
    case createWorkout
    case createWorkoutPlan

    var id: String {
        switch self {
        case let .videoDetail(videos, startIndex):
            return "videoDetail-\(videos[startIndex].id)"
        case let .exerciseCompletion(exercise):
            return "exerciseCompletion-\(exercise.id)"
        case let .userProfile(userId):
            return "userProfile-\(userId)"
        case .profile:
            return "profile"
        case let .videoFeed(videos, startIndex):
            return "videoFeed-\(videos.first?.first?.id ?? "")-\(startIndex)"
        case let .exercise(exercise):
            return "exercise-\(exercise.id)"
        case let .workout(workout):
            return "workout-\(workout.id)"
        case let .workoutPlan(plan):
            return "workoutPlan-\(plan.id)"
        case let .profileVideo(workoutPlan):
            return "profileVideo-\(workoutPlan.id)"
        case .createExercise:
            return "createExercise"
        case .createWorkout:
            return "createWorkout"
        case .createWorkoutPlan:
            return "createWorkoutPlan"
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Destination, rhs: Destination) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@ViewBuilder
func view(for destination: Destination) -> some View {
    switch destination {
    case let .videoDetail(videos, startIndex):
        VideoDetailView(
            videos: videos,
            startAt: startIndex,
            showBackButton: true,
            onBack: {
                withAnimation {
                    Navigator.shared.pop()
                }
            }
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
        VideoDetailView(
            videos: [exercise],
            startAt: 0,
            showBackButton: true,
            onBack: {
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .workout(workout):
        VideoDetailView(
            videos: workout.getAllVideos(),
            startAt: 0,
            showBackButton: true,
            onBack: {
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .workoutPlan(plan):
        VideoDetailView(
            videos: plan.getAllVideos(),
            startAt: 0,
            showBackButton: true,
            onBack: {
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .profileVideo(workoutPlan):
        ProfileVideoWrapper(workoutPlan: workoutPlan)
    case .createExercise:
        CreateExerciseView(onComplete: {
            Navigator.shared.pop()
        })
    case .createWorkout:
        CreateWorkoutView(onComplete: {
            Navigator.shared.pop()
        })
    case .createWorkoutPlan:
        CreateWorkoutPlanView(onComplete: {
            Navigator.shared.pop()
        })
    }
}

@MainActor
final class Navigator: ObservableObject {
    @Published var path = NavigationPath()
    @Published var presentedSheet: Destination?

    static let shared = Navigator()

    private func logNavigation(_ message: String) {
        // Remove logging
    }

    func navigate(to destination: Destination) {
        // Remove logging
        switch destination {
        case .videoDetail, .videoFeed, .profile, .userProfile,
             .exercise, .workout, .workoutPlan, .profileVideo,
             .createExercise, .createWorkout, .createWorkoutPlan:
            path.append(destination)
        case .exerciseCompletion:
            presentedSheet = destination
        }
    }

    func replace(with destination: Destination) {
        // Remove logging
        if !path.isEmpty {
            path.removeLast()
            path.append(destination)
        }
    }

    func pop() {
        // Remove logging
        withAnimation {
            if !path.isEmpty {
                path.removeLast()
            }
        }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
