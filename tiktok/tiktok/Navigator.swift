import SwiftUI

enum AppRoute: Hashable {
    case profile // Current user's profile
    case userProfile(userId: String) // Other user's profile
    case exercise(Exercise)
    case workout(Workout)
    case workoutPlan(WorkoutPlan)
    case videoDetail(workoutPlan: WorkoutPlan, workoutIndex: Int?, exerciseIndex: Int?)
    case exerciseCompletion(exercise: Exercise)
    case recommendedVideo(video: WorkoutPlan, recommendations: [VideoRecommendation])
    // Add additional routes as needed
}

enum Destination: Hashable, Identifiable {
    case videoDetail(workoutPlan: WorkoutPlan, workoutIndex: Int?, exerciseIndex: Int?)
    case exerciseCompletion(exercise: Exercise)
    case userProfile(userId: String)
    case profile
    case videoFeed(videos: [WorkoutPlan], startIndex: Int)

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
        case .videoDetail, .videoFeed:
            path.append(destination)
        default:
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
