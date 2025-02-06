import SwiftUI

enum AppRoute: Hashable {
    case profile // Current user's profile
    case userProfile(userId: String) // Other user's profile
    case exercise(Exercise)
    case workout(Workout)
    case workoutPlan(WorkoutPlan)
    case videoDetail(workoutPlan: WorkoutPlan, workoutIndex: Int?, exerciseIndex: Int?)
    case exerciseCompletion(exercise: Exercise)
    // Add additional routes as needed
}

final class Navigator: ObservableObject {
    @Published var path = NavigationPath()

    func navigate(to route: AppRoute) {
        path.append(route)
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
