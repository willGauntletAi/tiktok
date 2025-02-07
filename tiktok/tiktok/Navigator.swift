import SwiftUI

enum Destination: Hashable, Identifiable {
    case videoDetail(videos: [any VideoContent], startIndex: Int)
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
        case let .videoDetail(videos, startIndex):
            return "videoDetail-\(videos[startIndex].id)"
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
                print("🎬 Navigator: Popping view after back button tap")
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
                print("🎬 Navigator: Popping view after back button tap")
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .workout(workout):
        VideoDetailView(
            videos: workout.exercises,
            startAt: 0,
            showBackButton: true,
            onBack: {
                print("🎬 Navigator: Popping view after back button tap")
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .workoutPlan(plan):
        VideoDetailView(
            videos: plan.workouts.flatMap { $0.workout.exercises },
            startAt: 0,
            showBackButton: true,
            onBack: {
                print("🎬 Navigator: Popping view after back button tap")
                withAnimation {
                    Navigator.shared.pop()
                }
            }
        )
    case let .profileVideo(workoutPlan):
        ProfileVideoWrapper(workoutPlan: workoutPlan)
    }
}

@MainActor
final class Navigator: ObservableObject {
    @Published var path = NavigationPath()
    @Published var presentedSheet: Destination?
    
    static let shared = Navigator()

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

    func replace(with destination: Destination) {
        logNavigation("Replacing current view with \(destination.id)")
        if !path.isEmpty {
            path.removeLast()
            path.append(destination)
        }
    }

    func pop() {
        logNavigation("Popping view")
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
