import AVKit
import SwiftUI
import UIKit

struct VideoDetailView: View {
    let videos: [any VideoContent]
    let startIndex: Int
    let showBackButton: Bool
    let onBack: (() -> Void)?
    
    @StateObject private var viewModel: VideoDetailViewModel
    @State private var player: AVPlayer?
    @State private var isExpanded = false
    @State private var firstLineDescription: String = ""
    @State private var currentPosition: String?
    @State private var showComments = false
    @EnvironmentObject private var navigator: Navigator

    init(
        videos: [any VideoContent],
        startAt index: Int = 0,
        showBackButton: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        print("🎬 VideoDetailView: Initializing with startIndex: \(index)")
        print("🎬 VideoDetailView: Videos: \(videos.map { "\($0.id): \($0.title)" })")
        
        self.videos = videos
        self.startIndex = index
        self.showBackButton = showBackButton
        self.onBack = onBack
        
        // Initialize with the correct video ID based on startIndex
        let videoId = videos[index].id
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(videoId: videoId))
        _currentPosition = State(initialValue: videoId)
        
        print("🎬 VideoDetailView: Set initial videoId to: \(videoId)")
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
            // Debug print for showBackButton
            let _ = print("🔍 showBackButton value: \(showBackButton)")
            
            if videos.isEmpty {
                VStack {
                    Text("No videos to display")
                        .foregroundColor(.white)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ZStack(alignment: .top) {
                    // Main content
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                                ZStack {
                                    // Video Player
                                    if let videoUrl = URL(string: video.videoUrl) {
                                        VStack {
                                            Spacer()
                                            VideoPlayer(player: player ?? AVPlayer())
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                .aspectRatio(contentMode: .fit)
                                                .onAppear {
                                                    print("🎬 VideoDetailView: Video appeared at index \(index): \(video.id)")
                                                    if index == startIndex {
                                                        player = AVPlayer(url: videoUrl)
                                                        player?.play()
                                                    }
                                                }
                                                .onDisappear {
                                                    if index == startIndex {
                                                        player?.pause()
                                                        player = nil
                                                    }
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
                                    if index == startIndex {
                                        updateDescription(for: video)
                                        viewModel.updateVideoId(video.id)
                                    }
                                }
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentPosition)
                    .onAppear {
                        // Set initial scroll position to startIndex
                        print("🎬 VideoDetailView: Setting initial scroll position to video at index \(startIndex)")
                        currentPosition = videos[startIndex].id
                    }
                    .scrollDisabled(false)  // Ensure scrolling is enabled
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in
                                // Pause current video when dragging starts
                                player?.pause()
                            }
                            .onEnded { value in
                                // Resume playing if drag wasn't enough to change page
                                if abs(value.translation.width) < 50 {
                                    player?.play()
                                }
                            }
                    )

                    // Back button overlay
                    if showBackButton {
                        Button(action: {
                            print("🔙 Back button tapped")
                            withAnimation {
                                navigator.pop()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        }
                        .padding(.top, geometry.safeAreaInsets.top + 16)
                        .padding(.leading, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
