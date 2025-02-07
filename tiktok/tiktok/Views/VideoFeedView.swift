import AVKit
import SwiftUI

// Helper function moved to top level for reuse
private func getAllVideos(from workoutPlan: WorkoutPlan) -> [any VideoContent] {
    var allVideos: [any VideoContent] = []
    
    // Add the workout plan itself as it contains a video
    allVideos.append(workoutPlan)
    
    // Add each workout and its exercises
    for workoutMeta in workoutPlan.workouts {
        // Add the workout itself as it contains a video
        allVideos.append(workoutMeta.workout)
        // Add all exercises from the workout
        allVideos.append(contentsOf: workoutMeta.workout.exercises)
    }
    
    return allVideos
}

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
        ZStack(alignment: .top) {
            // Main content
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(videos, id: \.id) { workoutPlan in
                            VideoDetailView(
                                videos: workoutPlan.getAllVideos(),
                                startAt: 0
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
            
            // Back button at the highest level
            HStack {
                Button(action: {
                    print("🎬 Back button tapped")
                    navigator.pop()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4)
                }
                Spacer()
            }
            .padding(.top, UIApplication.shared.windows.first?.safeAreaInsets.top ?? 44 + 8)
            .padding(.horizontal, 16)
            .zIndex(1) // Ensure back button is always on top
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
