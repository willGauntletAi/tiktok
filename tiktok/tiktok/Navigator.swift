import SwiftUI

enum AppRoute: Hashable {
  case profile
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
