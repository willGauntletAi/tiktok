import SwiftUI

struct ProfileView: View {
  @StateObject private var viewModel = ProfileViewModel()
  @State private var selectedTab = 0

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(spacing: 20) {
          // Profile Header
          if let user = viewModel.user {
            ProfileHeaderView(user: user)
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
        .navigationTitle("Profile")
        .toolbar {
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

struct VideoGridView: View {
  let videos: [ProfileViewModel.Video]
  let columns = [
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1),
    GridItem(.flexible(), spacing: 1),
  ]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 1) {
        ForEach(videos) { video in
          NavigationLink(
            destination: ExerciseDetailView(
              exercise: Exercise(
                id: video.id,
                type: video.type.rawValue,
                title: video.title,
                description: video.description,
                instructorId: video.instructorId,
                videoUrl: video.videoUrl,
                thumbnailUrl: video.thumbnailUrl,
                difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                targetMuscles: video.targetMuscles,
                duration: 0,  // Since ProfileViewModel.Video doesn't have duration
                createdAt: video.createdAt,
                updatedAt: video.updatedAt
              ))
          ) {
            VideoThumbnailView(video: video)
              .frame(height: UIScreen.main.bounds.width / 3)
          }
        }
      }
      .padding(.horizontal, 1)
    }
  }
}

struct VideoThumbnailView: View {
  let video: ProfileViewModel.Video

  var body: some View {
    GeometryReader { geometry in
      AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
        switch phase {
        case .empty:
          ZStack {
            Color.gray.opacity(0.2)
            ProgressView()
          }

        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)

        case .failure:
          ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "exclamationmark.triangle")
              .foregroundColor(.gray)
          }

        @unknown default:
          Color.gray.opacity(0.2)
        }
      }
      .clipped()
      .overlay(alignment: .bottomLeading) {
        Text(video.type.rawValue.capitalized)
          .font(.caption2)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.black.opacity(0.6))
          .foregroundColor(.white)
          .cornerRadius(4)
          .padding(4)
      }
    }
  }
}

#Preview {
  ProfileView()
}
