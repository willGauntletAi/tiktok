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
  @StateObject private var navigator = Navigator()
  @State private var selectedTab = 0

  private func logNavigation(_ message: String) {
    print("🎬 ContentView: \(message)")
  }

  var body: some View {
    NavigationStack(path: $navigator.path) {
      Group {
        if authService.isAuthenticated {
          TabView(selection: $selectedTab) {
            SearchView()
              .tabItem {
                Label("Search", systemImage: "magnifyingglass")
              }
              .tag(0)

            CreateSelectionView()
              .tabItem {
                Label("Create", systemImage: "plus.square")
              }
              .tag(1)

            ProfileView()
              .tabItem {
                Label("Profile", systemImage: "person")
              }
              .tag(2)
          }
          .navigationDestination(for: Destination.self) { destination in
            view(for: destination)
              .onAppear {
                logNavigation("Creating view for destination: \(destination.id)")
                logNavigation("Current path count: \(navigator.path.count)")
              }
          }
        } else {
          LoginView()
        }
      }
    }
    .onChange(of: navigator.path) { newPath in
      logNavigation("Navigation path changed")
      logNavigation("New path count: \(newPath.count)")
    }
    .sheet(item: $navigator.presentedSheet) { destination in
      view(for: destination)
    }
    .fullScreenCover(item: $navigator.presentedFullScreenCover) { destination in
      view(for: destination)
    }
    .environmentObject(navigator)
  }
}
