//
//  ContentView.swift
//  tiktok
//
//  Created by Wilbert Feldman on 2/3/25.
//

import SwiftUI
import FirebaseCore

struct ContentView: View {
    var body: some View {
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
    }
}

#Preview {
    ContentView()
}
