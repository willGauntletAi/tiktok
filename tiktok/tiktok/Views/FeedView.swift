import AVKit
import FirebaseFirestore
import SwiftUI

struct FeedView: View {
    @State private var currentIndex: Int?
    @State private var videos: [any VideoContent] = []
    @State private var isLoading = false
    @EnvironmentObject private var navigator: Navigator
    private let recommendationService = RecommendationService()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                        VideoPageView(
                            video: video,
                            isPlaying: index == currentIndex
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                        .onAppear {
                            print("🎬 Video at index \(index) appeared")
                            withAnimation {
                                currentIndex = index
                            }
                            if index >= videos.count - 2 && !isLoading {
                                Task {
                                    await loadMoreVideos()
                                }
                            }
                        }
                        .onDisappear {
                            if currentIndex == index {
                                print("🎬 Video at index \(index) disappeared, stopping playback")
                                withAnimation {
                                    currentIndex = nil
                                }
                            }
                        }
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)
            .onChange(of: currentIndex) { oldValue, newValue in
                if let oldIndex = oldValue, oldIndex != newValue {
                    print("🎬 Stopping video at index \(oldIndex)")
                }
                if let newIndex = newValue {
                    print("🎬 Starting video at index \(newIndex)")
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if videos.isEmpty {
                await loadMoreVideos()
            }
        }
        .onDisappear {
            currentIndex = nil
        }
    }

    private func loadMoreVideos() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let recommendations = try await recommendationService.getRecommendations(
                forVideos: videos.map { $0.id }
            )

            let db = Firestore.firestore()
            var newVideos: [any VideoContent] = []

            for recommendation in recommendations {
                do {
                    let doc = try await db.collection("videos").document(recommendation.videoId).getDocument()
                    guard let data = doc.data() else { continue }

                    let type = data["type"] as? String ?? ""
                    switch type {
                    case "exercise":
                        let exercise = Exercise(
                            id: doc.documentID,
                            type: type,
                            title: data["title"] as? String ?? "",
                            description: data["description"] as? String ?? "",
                            instructorId: data["instructorId"] as? String ?? "",
                            videoUrl: data["videoUrl"] as? String ?? "",
                            thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
                            difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner,
                            targetMuscles: data["targetMuscles"] as? [String] ?? [],
                            duration: data["duration"] as? Int ?? 0,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                        newVideos.append(exercise)

                    case "workout":
                        let workout = Workout(
                            id: doc.documentID,
                            title: data["title"] as? String ?? "",
                            description: data["description"] as? String ?? "",
                            exercises: [], // We'll fetch exercises separately if needed
                            instructorId: data["instructorId"] as? String ?? "",
                            videoUrl: data["videoUrl"] as? String ?? "",
                            thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
                            difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner,
                            targetMuscles: data["targetMuscles"] as? [String] ?? [],
                            totalDuration: data["totalDuration"] as? Int ?? 0,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                        newVideos.append(workout)

                    case "workoutPlan":
                        let workoutPlan = WorkoutPlan(
                            id: doc.documentID,
                            title: data["title"] as? String ?? "",
                            description: data["description"] as? String ?? "",
                            instructorId: data["instructorId"] as? String ?? "",
                            videoUrl: data["videoUrl"] as? String ?? "",
                            thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
                            difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner,
                            targetMuscles: data["targetMuscles"] as? [String] ?? [],
                            workouts: [], // We'll fetch workouts separately if needed
                            duration: data["duration"] as? Int ?? 7,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                        newVideos.append(workoutPlan)

                    default:
                        print("❌ Unknown video type: \(type)")
                    }
                } catch {
                    print("❌ Error processing video recommendation: \(error)")
                }
            }

            await MainActor.run {
                if !newVideos.isEmpty {
                    videos.append(contentsOf: newVideos)
                }
            }
        } catch {
            print("❌ Error loading more videos: \(error)")
        }
    }
}
