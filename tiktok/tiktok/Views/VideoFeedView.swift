import AVKit
import SwiftUI

struct ProfileVideoWrapper: View {
    let workoutPlan: WorkoutPlan
    @EnvironmentObject private var navigator: Navigator

    var body: some View {
        VideoDetailView(
            videos: workoutPlan.getAllVideos(),
            startAt: 0
        )
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 {
                        print("🎬 Left swipe detected, popping navigation")
                        navigator.pop()
                    }
                }
        )
    }
}

struct VideoFeedView: View {
    let initialVideos: [WorkoutPlan]
    let initialIndex: Int

    @State private var currentVideoId: String?
    @State private var videos: [WorkoutPlan]
    @State private var isLoadingMore = false
    @State private var recommendations: [VideoRecommendation] = []
    @EnvironmentObject private var navigator: Navigator

    private let recommendationService = RecommendationService()

    init(initialVideos: [WorkoutPlan], startingAt index: Int = 0) {
        self.initialVideos = initialVideos
        initialIndex = index
        // Initialize state variables
        _videos = State(initialValue: initialVideos)
        _currentVideoId = State(initialValue: initialVideos.isEmpty ? nil : initialVideos[index].id)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(videos, id: \.id) { workoutPlan in
                        VideoDetailView(
                            videos: workoutPlan.getAllVideos(),
                            startAt: 0,
                            showBackButton: true,
                            onBack: {
                                print("🎬 Back button tapped")
                                navigator.pop()
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(workoutPlan.id)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentVideoId)
            .onChange(of: currentVideoId) { _, newValue in
                if let videoId = newValue {
                    print("🎬 Scrolled to video: \(videoId)")
                    if let index = videos.firstIndex(where: { $0.id == videoId }),
                       index >= videos.count - 2
                    {
                        // Load more videos when we're close to the end
                        Task {
                            await loadMoreVideos()
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 {
                        print("🎬 Left swipe detected, popping navigation")
                        navigator.pop()
                    }
                }
        )
        .task {
            // Only load more if we have initial videos to base recommendations on
            if !initialVideos.isEmpty {
                await loadMoreVideos()
            }
        }
    }

    private func loadMoreVideos() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            // Use the last few videos to get recommendations
            let videoIds = videos.suffix(4).map { $0.id }
            print("🎬 Getting recommendations based on: \(videoIds)")

            let newRecommendations = try await recommendationService.getRecommendations(
                forVideos: videoIds
            )

            // Filter out only recommendations that have valid video data
            let newVideos = newRecommendations.compactMap { $0.video }
            print("🎬 Got \(newVideos.count) new recommended videos")

            // Update recommendations for next batch
            recommendations = newRecommendations

            // Append new videos to our list
            await MainActor.run {
                videos.append(contentsOf: newVideos)
            }
        } catch {
            print("❌ Error loading more videos: \(error)")
        }
    }
}

#Preview {
    VideoFeedView(initialVideos: [], startingAt: 0)
}
