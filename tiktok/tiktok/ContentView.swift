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

  var body: some View {
    Group {
      if authService.isAuthenticated {
        TabView {
          NavigationView {
            FeedView()
          }
          .tabItem {
            Label("Feed", systemImage: "play.square")
          }

          NavigationView {
            CreateExerciseView()
          }
          .tabItem {
            Label("Create", systemImage: "plus.square")
          }

          NavigationView {
            ProfileView()
          }
          .tabItem {
            Label("Profile", systemImage: "person")
          }
        }
      } else {
        LoginView()
      }
    }
  }
}
