//
//  ContentView.swift
//  tiktok
//
//  Created by Wilbert Feldman on 2/3/25.
//

import FirebaseAuth
import FirebaseCore
import SwiftUI

struct ContentView: View {
  @StateObject private var authService = AuthService.shared
  @StateObject private var navigationVM = NavigationViewModel.shared

  var body: some View {
    Group {
      if authService.isAuthenticated {
        TabView(selection: $navigationVM.selectedTab) {
          NavigationView {
            SearchView()
          }
          .tabItem {
            Label("Search", systemImage: "magnifyingglass")
          }
          .tag(0)

          CreateSelectionView()
            .tabItem {
              Label("Create", systemImage: "plus.square")
            }
            .tag(1)

          NavigationView {
            ProfileView()
          }
          .tabItem {
            Label("Profile", systemImage: "person")
          }
          .tag(2)
        }
        .environmentObject(navigationVM)
      } else {
        LoginView()
      }
    }
  }
}
