import AVKit
import SwiftUI
import UIKit

struct VideoDetailView: View {
    let videos: [any VideoContent]
    let startIndex: Int
    @StateObject private var viewModel: VideoDetailViewModel
    @State private var player: AVPlayer?
    @State private var isExpanded = false
    @State private var firstLineDescription: String = ""
    @State private var currentPosition: String?
    @State private var showComments = false
    @EnvironmentObject private var navigator: Navigator

    init(videos: [any VideoContent], startAt index: Int = 0) {
        self.videos = videos
        self.startIndex = index
        let videoId = videos[index].id
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(videoId: videoId))
        _currentPosition = State(initialValue: videoId)
    }

    private func updateDescription(for video: any VideoContent) {
        if let firstLine = video.description.components(separatedBy: .newlines).first {
            firstLineDescription = firstLine
        } else {
            firstLineDescription = video.description
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if videos.isEmpty {
                VStack {
                    Text("No videos to display")
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                            ZStack(alignment: .bottomLeading) {
                                // Video Player
                                if let videoUrl = URL(string: video.videoUrl) {
                                    VStack {
                                        Spacer()
                                        VideoPlayer(player: player ?? AVPlayer())
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .aspectRatio(contentMode: .fit)
                                            .onAppear {
                                                player = AVPlayer(url: videoUrl)
                                                player?.play()
                                            }
                                            .onDisappear {
                                                player?.pause()
                                                player = nil
                                            }
                                        Spacer()
                                    }
                                    .edgesIgnoringSafeArea(.all)
                                }

                                // Right side buttons
                                VStack {
                                    Spacer()
                                    VStack(spacing: 20) {
                                        // Like Button
                                        Button(action: {
                                            Task {
                                                await viewModel.toggleLike()
                                            }
                                        }) {
                                            Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                                .font(.system(size: 28))
                                                .foregroundColor(viewModel.isLiked ? .red : .white)
                                                .shadow(radius: 2)
                                        }
                                        .disabled(viewModel.isLoading)
                                        .accessibilityLabel("Like Video")
                                        .accessibilityAddTraits(viewModel.isLiked ? .isSelected : [])
                                        .overlay {
                                            if viewModel.isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            }
                                        }

                                        // Profile Button
                                        Button(action: {
                                            navigator.navigate(to: .userProfile(userId: video.instructorId))
                                        }) {
                                            VStack {
                                                Image(systemName: "person.circle.fill")
                                                    .font(.system(size: 28))
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)

                                                Text("@\(viewModel.instructorName)")
                                                    .font(.caption)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .accessibilityLabel("View Profile")
                                        .accessibilityValue("@\(viewModel.instructorName)")

                                        // Comment Button
                                        Button(action: {
                                            showComments = true
                                        }) {
                                            VStack {
                                                Image(systemName: "bubble.left")
                                                    .font(.system(size: 28))
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)

                                                Text("Comments")
                                                    .font(.caption)
                                                    .foregroundColor(.white)
                                                    .shadow(radius: 2)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .accessibilityLabel("View Comments")

                                        // Exercise Completion Button
                                        if video is Exercise {
                                            Button(action: {
                                                navigator.navigate(to: .exerciseCompletion(exercise: video as! Exercise))
                                            }) {
                                                VStack {
                                                    Image(systemName: "checkmark.circle")
                                                        .font(.system(size: 28))
                                                        .foregroundColor(.white)
                                                        .shadow(radius: 2)

                                                    Text("Complete")
                                                        .font(.caption)
                                                        .foregroundColor(.white)
                                                        .shadow(radius: 2)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .accessibilityLabel("Record Exercise Completion")
                                        }
                                    }
                                    .frame(width: 80)
                                    .padding(.trailing, 16)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)

                                // Content Overlay
                                VStack {
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Title
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(video.title)
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .shadow(radius: 2)
                                        }

                                        // Description
                                        Text(isExpanded ? video.description : firstLineDescription)
                                            .font(.body)
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                            .lineLimit(isExpanded ? nil : 1)
                                            .onAppear {
                                                updateDescription(for: video)
                                            }

                                        if isExpanded {
                                            // Additional details
                                            VStack(alignment: .leading, spacing: 12) {
                                                DetailRow(
                                                    title: "Difficulty",
                                                    value: video.difficulty.rawValue.capitalized
                                                )
                                                DetailRow(
                                                    title: "Target Muscles",
                                                    value: video.targetMuscles.joined(separator: ", ")
                                                )
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(
                                                colors: [.black.opacity(0.7), .black.opacity(0.4), .clear]
                                            ),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: isExpanded ? .infinity : geometry.size.width * 0.8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut) {
                                            isExpanded.toggle()
                                        }
                                    }
                                }
                            }
                            .frame(width: geometry.size.width)
                            .id(video.id)
                            .onAppear {
                                updateDescription(for: video)
                                viewModel.updateVideoId(video.id)
                            }
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentPosition)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let firstVideo = videos.first {
                updateDescription(for: firstVideo)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .sheet(isPresented: $showComments) {
            CommentSheetView(viewModel: CommentViewModel(videoId: viewModel.videoId))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .shadow(radius: 2)

            Text(value)
                .font(.body)
                .foregroundColor(.white)
                .shadow(radius: 2)
        }
    }
}
