import SwiftUI

enum AppRoute: Hashable {
  case profile  // Current user's profile
  case userProfile(userId: String)  // Other user's profile
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
  case recommendedVideo(video: WorkoutPlan, recommendations: [VideoRecommendation])
  case userProfile(userId: String)
  case profile
  // Add additional routes as needed

  var id: String {
    switch self {
    case let .videoDetail(workoutPlan, _, _):
      return "videoDetail-\(workoutPlan.id)"
    case let .exerciseCompletion(exercise):
      return "exerciseCompletion-\(exercise.id)"
    case let .recommendedVideo(video, _):
      return "recommendedVideo-\(video.id)"
    case let .userProfile(userId):
      return "userProfile-\(userId)"
    case .profile:
      return "profile"
    }
  }

  var isVerticalTransition: Bool {
    print("🎬 Checking transition type for destination: \(self.id)")
    switch self {
    case .recommendedVideo:
      print("🎬 Using vertical transition for recommended video")
      return true
    default:
      print("🎬 Using horizontal transition for \(self.id)")
      return false
    }
  }
}

enum NavigationTransitionStyle {
  case vertical
  case horizontal
}

final class Navigator: ObservableObject {
  @Published var path = NavigationPath()
  @Published var presentedSheet: Destination?
  @Published var presentedFullScreenCover: Destination?

  private func logNavigation(_ message: String) {
    print("🎬 Navigator: \(message)")
  }

  func navigate(to destination: Destination) {
    logNavigation("Navigating to \(destination.id)")
    logNavigation("Current path count: \(path.count)")
    logNavigation("Using vertical transition: \(destination.isVerticalTransition)")

    switch destination {
    case .videoDetail, .recommendedVideo:
      logNavigation("Appending to navigation path")
      withAnimation(.easeInOut(duration: 0.3)) {
        path.append(destination)
      }
    default:
      logNavigation("Presenting as sheet")
      presentedSheet = destination
    }
    logNavigation("New path count: \(path.count)")
  }

  func pop() {
    withAnimation(.easeInOut(duration: 0.3)) {
      if !path.isEmpty {
        path.removeLast()
      }
    }
  }

  func popToRoot() {
    withAnimation(.easeInOut(duration: 0.3)) {
      path = NavigationPath()
    }
  }
}

struct VerticalSlideTransition: ViewModifier {
  let isPresented: Bool

  func body(content: Content) -> some View {
    content
      .transition(
        .asymmetric(
          insertion: .move(edge: .bottom),
          removal: .move(edge: .top)
        )
      )
  }
}

@ViewBuilder
func view(for destination: Destination) -> some View {
  switch destination {
  case let .videoDetail(workoutPlan, workoutIndex, exerciseIndex):
    VideoDetailView(
      workoutPlan: workoutPlan, workoutIndex: workoutIndex, exerciseIndex: exerciseIndex
    )
    .navigationTransition(.push)
  case let .recommendedVideo(video, recommendations):
    VideoDetailView(workoutPlan: video, recommendations: recommendations)
      .navigationTransition(.moveUp)
  case let .exerciseCompletion(exercise):
    ExerciseCompletionView(exercise: exercise)
  case let .userProfile(userId):
    ProfileView(userId: userId)
  case .profile:
    ProfileView()
  }
}
