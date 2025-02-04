import SwiftUI

@MainActor
class NavigationViewModel: ObservableObject {
  @Published var selectedTab = 0

  static let shared = NavigationViewModel()

  private init() {}

  func navigateToProfile() {
    selectedTab = 2  // Index of the profile tab
  }
}
