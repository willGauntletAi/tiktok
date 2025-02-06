import FirebaseAuth
import SwiftUI

struct ProfileView: View {
  @StateObject private var viewModel: ProfileViewModel
  @State private var selectedTab = 0
  @EnvironmentObject private var navigator: Navigator

  init(userId: String? = nil) {
    _viewModel = StateObject(wrappedValue: ProfileViewModel(userId: userId))
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        // Profile Header
        if let user = viewModel.user {
          ProfileHeaderView(user: user)
            .onTapGesture {
              // Only show follow button if this is not the current user's profile
              if viewModel.userId != nil {
                // TODO: Implement follow functionality
              }
            }
        }

        // Content Tabs
        VStack(spacing: 0) {
          // Tab Buttons
          HStack(spacing: 0) {
            TabButton(title: "My Videos", isSelected: selectedTab == 0) {
              selectedTab = 0
            }
            TabButton(title: "Liked", isSelected: selectedTab == 1) {
              selectedTab = 1
            }
          }

          // Tab Content
          if selectedTab == 0 {
            if viewModel.userVideos.isEmpty {
              Text("No videos yet")
                .foregroundColor(.gray)
                .padding()
            } else {
              VideoGridView(videos: viewModel.userVideos)
                .frame(minHeight: 200)
            }
          } else {
            if viewModel.likedVideos.isEmpty {
              Text("No liked videos")
                .foregroundColor(.gray)
                .padding()
            } else {
              VideoGridView(videos: viewModel.likedVideos)
                .frame(minHeight: 200)
            }
          }
        }
      }
      .navigationTitle(
        viewModel.userId == nil ? "Profile" : "@\(viewModel.user?.displayName ?? "")"
      )
      .toolbar {
        // Only show settings menu for current user's profile
        if viewModel.userId == nil {
          ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
              Button(
                role: .destructive,
                action: {
                  viewModel.signOut()
                }
              ) {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
              }
            } label: {
              Image(systemName: "gearshape.fill")
                .foregroundColor(.primary)
            }
          }
        }
      }
      .overlay {
        if viewModel.isLoading {
          ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.2))
        }
      }
      .alert("Error", isPresented: .constant(viewModel.error != nil)) {
        Button("OK") {
          viewModel.error = nil
        }
      } message: {
        Text(viewModel.error ?? "")
      }
    }
    .task {
      await viewModel.fetchUserProfile()
    }
  }
}

struct ProfileHeaderView: View {
  let user: ProfileViewModel.User
  @State private var isFollowing = false  // Add state for follow button

  var body: some View {
    VStack(spacing: 16) {
      // Profile Image
      Circle()
        .fill(Color.gray.opacity(0.2))
        .frame(width: 100, height: 100)
        .overlay(
          Text(String(user.displayName.prefix(1)).uppercased())
            .font(.system(size: 40, weight: .bold))
            .foregroundColor(.gray)
        )

      // User Info
      VStack(spacing: 8) {
        Text(user.displayName)
          .font(.title2)
          .fontWeight(.bold)

        Text(user.email)
          .font(.subheadline)
          .foregroundColor(.gray)

        Text("Member since \(user.createdAt.formatted(.dateTime.month().year()))")
          .font(.caption)
          .foregroundColor(.gray)

        // Follow Button (only show for other users' profiles)
        if user.id != Auth.auth().currentUser?.uid {
          Button(action: {
            isFollowing.toggle()
            // TODO: Implement follow/unfollow functionality
          }) {
            Text(isFollowing ? "Following" : "Follow")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(isFollowing ? .primary : .white)
              .padding(.horizontal, 24)
              .padding(.vertical, 8)
              .background(isFollowing ? Color.gray.opacity(0.2) : Color.blue)
              .cornerRadius(20)
          }
        }
      }
    }
    .padding()
  }
}

struct TabButton: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Text(title)
          .fontWeight(isSelected ? .bold : .regular)
          .foregroundColor(isSelected ? .primary : .gray)

        Rectangle()
          .fill(isSelected ? Color.blue : Color.clear)
          .frame(height: 2)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

#Preview {
  ProfileView()
}
