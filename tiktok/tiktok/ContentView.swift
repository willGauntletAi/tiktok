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
                    }
                } else {
                    LoginView()
                }
            }
        }
        .sheet(item: $navigator.presentedSheet) { destination in
            view(for: destination)
        }
        .environmentObject(navigator)
    }
}
