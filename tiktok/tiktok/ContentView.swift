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

    var body: some View {
        Group {
            if authService.isAuthenticated {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $navigator.path) {
                        SearchView()
                            .navigationDestination(for: AppRoute.self) { route in
                                switch route {
                                case .profile:
                                    ProfileView()
                                case let .userProfile(userId):
                                    ProfileView(userId: userId)
                                case let .videoDetail(workoutPlan, workoutIndex, exerciseIndex):
                                    VideoDetailView(
                                        workoutPlan: workoutPlan,
                                        workoutIndex: workoutIndex,
                                        exerciseIndex: exerciseIndex
                                    )
                                case let .exerciseCompletion(exercise):
                                    ExerciseCompletionView(exercise: exercise)
                                case .exercise, .workout, .workoutPlan:
                                    // These are handled by converting to videoDetail in the ContentCard
                                    EmptyView()
                                }
                            }
                    }
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(0)

                    NavigationStack(path: $navigator.path) {
                        CreateSelectionView()
                            .navigationDestination(for: AppRoute.self) { route in
                                switch route {
                                case .profile:
                                    ProfileView()
                                case let .userProfile(userId):
                                    ProfileView(userId: userId)
                                case let .videoDetail(workoutPlan, workoutIndex, exerciseIndex):
                                    VideoDetailView(
                                        workoutPlan: workoutPlan,
                                        workoutIndex: workoutIndex,
                                        exerciseIndex: exerciseIndex
                                    )
                                case let .exerciseCompletion(exercise):
                                    ExerciseCompletionView(exercise: exercise)
                                case .exercise, .workout, .workoutPlan:
                                    EmptyView()
                                }
                            }
                    }
                    .tabItem {
                        Label("Create", systemImage: "plus.square")
                    }
                    .tag(1)

                    NavigationStack(path: $navigator.path) {
                        ProfileView()
                            .navigationDestination(for: AppRoute.self) { route in
                                switch route {
                                case .profile:
                                    ProfileView()
                                case let .userProfile(userId):
                                    ProfileView(userId: userId)
                                case let .videoDetail(workoutPlan, workoutIndex, exerciseIndex):
                                    VideoDetailView(
                                        workoutPlan: workoutPlan,
                                        workoutIndex: workoutIndex,
                                        exerciseIndex: exerciseIndex
                                    )
                                case let .exerciseCompletion(exercise):
                                    ExerciseCompletionView(exercise: exercise)
                                case .exercise, .workout, .workoutPlan:
                                    EmptyView()
                                }
                            }
                    }
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(2)
                }
                .environmentObject(navigator)
            } else {
                LoginView()
            }
        }
    }
}
