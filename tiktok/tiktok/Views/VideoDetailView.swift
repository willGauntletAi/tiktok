import AVKit
import SwiftUI
import UIKit

struct VideoDetailView: View {
    let videos: [any VideoContent]
    let startIndex: Int
    let showBackButton: Bool
    let onBack: (() -> Void)?

    @State private var currentPosition: String?
    @EnvironmentObject private var navigator: Navigator

    init(
        videos: [any VideoContent],
        startAt index: Int = 0,
        showBackButton: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.videos = videos
        self.startIndex = index
        self.showBackButton = showBackButton
        self.onBack = onBack
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Main content
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                            VideoPageView(video: video)
                                .frame(width: geometry.size.width)
                                .id(video.id)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentPosition)
                .onAppear {
                    currentPosition = videos[startIndex].id
                }

                // Back button overlay
                if showBackButton {
                    Button(action: {
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
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }
}

// Separate view for each video page
struct VideoPageView: View {
    let video: any VideoContent
    
    @StateObject private var viewModel: VideoDetailViewModel
    @State private var player: AVPlayer?
    @State private var isExpanded = false
    @State private var showComments = false
    @EnvironmentObject private var navigator: Navigator
    
    init(video: any VideoContent) {
        self.video = video
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(videoId: video.id))
    }
    
    private var description: String {
        isExpanded ? video.description : (video.description.components(separatedBy: .newlines).first ?? video.description)
    }
    
    var body: some View {
        ZStack {
            // Video Player
            if let videoUrl = URL(string: video.videoUrl) {
                VideoPlayer(player: player ?? AVPlayer())
                    .onAppear {
                        player = AVPlayer(url: videoUrl)
                        player?.play()
                    }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            }
            
            // Overlay content
            ZStack {
                // Right side buttons
                VStack(spacing: 20) {
                    Spacer()
                    
                    Button(action: { Task { await viewModel.toggleLike() }}) {
                        VStack {
                            Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 28))
                                .foregroundColor(viewModel.isLiked ? .red : .white)
                            
                            Text("Like")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Button(action: {
                        navigator.navigate(to: .userProfile(userId: video.instructorId))
                    }) {
                        VStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                            
                            Text("@\(viewModel.instructorName)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    
                    Button(action: { showComments = true }) {
                        VStack {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                            
                            Text("Comments")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    
                    if video is Exercise {
                        Button(action: {
                            navigator.navigate(to: .exerciseCompletion(exercise: video as! Exercise))
                        }) {
                            VStack {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                
                                Text("Complete")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                
                // Bottom content
                VStack {
                    Spacer()
                    
                    // Video info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(description)
                            .lineLimit(isExpanded ? nil : 1)
                            .onTapGesture {
                                withAnimation {
                                    isExpanded.toggle()
                                }
                            }
                        
                        if isExpanded {
                            DetailRow(title: "Difficulty", value: video.difficulty.rawValue.capitalized)
                            DetailRow(title: "Target Muscles", value: video.targetMuscles.joined(separator: ", "))
                        }
                    }
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.black.opacity(0.7), .black.opacity(0.4), .clear]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showComments) {
            CommentSheetView(viewModel: CommentViewModel(videoId: video.id))
                .presentationDetents([.medium, .large])
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
