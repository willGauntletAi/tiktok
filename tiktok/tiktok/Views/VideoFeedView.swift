import AVKit
import SwiftUI
import FirebaseFirestore

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
    let initialVideos: [[any VideoContent]]
    let initialIndex: Int

    @State private var currentVideoId: String?
    @State private var videos: [[any VideoContent]]
    @State private var isLoadingMore = false
    @State private var recommendations: [VideoRecommendation] = []
    @EnvironmentObject private var navigator: Navigator

    private let recommendationService = RecommendationService()

    init(initialVideos: [[any VideoContent]], startingAt index: Int = 0) {
        self.initialVideos = initialVideos
        initialIndex = index
        // Initialize state variables
        _videos = State(initialValue: initialVideos)
        _currentVideoId = State(initialValue: initialVideos.isEmpty ? nil : initialVideos[index].first?.id)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, videoList in
                        VideoDetailView(
                            videos: videoList,
                            startAt: 0,
                            showBackButton: true,
                            onBack: {
                                print("🎬 Back button tapped")
                                navigator.pop()
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id("\(index)-\(videoList.first?.id ?? UUID().uuidString)")
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentVideoId)
            .onChange(of: currentVideoId) { _, newValue in
                if let videoId = newValue {
                    print("🎬 Scrolled to video: \(videoId)")
                    if let index = videos.firstIndex(where: { $0.first?.id == videoId }),
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

    private func handleVideoDocument(_ doc: DocumentSnapshot, db: Firestore) async throws -> [any VideoContent] {
        guard let data = doc.data() else { return [] }
        
        let type = data["type"] as? String ?? ""
        var videosToShow: [any VideoContent] = []

        switch type {
        case "exercise":
            // For exercises, just create and add the exercise itself
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
            videosToShow = [exercise]
            
        case "workout":
            // Fetch the complete workout with its exercises
            let workout = Workout(
                id: doc.documentID,
                title: data["title"] as? String ?? "",
                description: data["description"] as? String ?? "",
                exercises: [], // We'll add these next
                instructorId: data["instructorId"] as? String ?? "",
                videoUrl: data["videoUrl"] as? String ?? "",
                thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
                difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner,
                targetMuscles: data["targetMuscles"] as? [String] ?? [],
                totalDuration: data["totalDuration"] as? Int ?? 0,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            var exercises: [Exercise] = []
            // Fetch and add exercises
            if let exerciseDicts = data["exercises"] as? [[String: Any]] {
                for exerciseDict in exerciseDicts {
                    if let exerciseId = exerciseDict["id"] as? String {
                        let exerciseDoc = try await db.collection("videos").document(exerciseId).getDocument()
                        if let exerciseData = exerciseDoc.data() {
                            let exercise = Exercise(
                                id: exerciseId,
                                type: "exercise",
                                title: exerciseData["title"] as? String ?? "",
                                description: exerciseData["description"] as? String ?? "",
                                instructorId: exerciseData["instructorId"] as? String ?? "",
                                videoUrl: exerciseData["videoUrl"] as? String ?? "",
                                thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
                                difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "beginner") ?? .beginner,
                                targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                                duration: exerciseData["duration"] as? Int ?? 0,
                                createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                            )
                            exercises.append(exercise)
                        }
                    }
                }
            }
            
            // Create a new workout with all exercises
            let completeWorkout = Workout(
                id: workout.id,
                title: workout.title,
                description: workout.description,
                exercises: exercises,
                instructorId: workout.instructorId,
                videoUrl: workout.videoUrl,
                thumbnailUrl: workout.thumbnailUrl,
                difficulty: workout.difficulty,
                targetMuscles: workout.targetMuscles,
                totalDuration: workout.totalDuration,
                createdAt: workout.createdAt,
                updatedAt: workout.updatedAt
            )
            videosToShow = [completeWorkout] + exercises
            
        case "workoutPlan":
            // Create the workout plan
            let workoutPlan = WorkoutPlan(
                id: doc.documentID,
                title: data["title"] as? String ?? "",
                description: data["description"] as? String ?? "",
                instructorId: data["instructorId"] as? String ?? "",
                videoUrl: data["videoUrl"] as? String ?? "",
                thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
                difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner,
                targetMuscles: data["targetMuscles"] as? [String] ?? [],
                workouts: [], // We'll add workouts next
                duration: data["duration"] as? Int ?? 7,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            var workoutsWithMetadata: [WorkoutWithMetadata] = []
            // Fetch and add workouts and their exercises
            if let workoutDicts = data["workouts"] as? [[String: Any]] {
                for workoutDict in workoutDicts {
                    if let workoutId = workoutDict["id"] as? String {
                        let workoutDoc = try await db.collection("videos").document(workoutId).getDocument()
                        if let workoutData = workoutDoc.data() {
                            var exercises: [Exercise] = []
                            // Add workout's exercises
                            if let exerciseDicts = workoutData["exercises"] as? [[String: Any]] {
                                for exerciseDict in exerciseDicts {
                                    if let exerciseId = exerciseDict["id"] as? String {
                                        let exerciseDoc = try await db.collection("videos").document(exerciseId).getDocument()
                                        if let exerciseData = exerciseDoc.data() {
                                            let exercise = Exercise(
                                                id: exerciseId,
                                                type: "exercise",
                                                title: exerciseData["title"] as? String ?? "",
                                                description: exerciseData["description"] as? String ?? "",
                                                instructorId: exerciseData["instructorId"] as? String ?? "",
                                                videoUrl: exerciseData["videoUrl"] as? String ?? "",
                                                thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
                                                difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "beginner") ?? .beginner,
                                                targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                                                duration: exerciseData["duration"] as? Int ?? 0,
                                                createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                                updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                                            )
                                            exercises.append(exercise)
                                        }
                                    }
                                }
                            }
                            
                            // Create workout with exercises
                            let workout = Workout(
                                id: workoutId,
                                title: workoutData["title"] as? String ?? "",
                                description: workoutData["description"] as? String ?? "",
                                exercises: exercises,
                                instructorId: workoutData["instructorId"] as? String ?? "",
                                videoUrl: workoutData["videoUrl"] as? String ?? "",
                                thumbnailUrl: workoutData["thumbnailUrl"] as? String ?? "",
                                difficulty: Difficulty(rawValue: workoutData["difficulty"] as? String ?? "beginner") ?? .beginner,
                                targetMuscles: workoutData["targetMuscles"] as? [String] ?? [],
                                totalDuration: workoutData["totalDuration"] as? Int ?? 0,
                                createdAt: (workoutData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                updatedAt: (workoutData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                            )
                            
                            let workoutWithMetadata = WorkoutWithMetadata(
                                workout: workout,
                                weekNumber: workoutDict["weekNumber"] as? Int ?? 1,
                                dayOfWeek: workoutDict["dayOfWeek"] as? Int ?? 1
                            )
                            workoutsWithMetadata.append(workoutWithMetadata)
                            
                            // Add workout and its exercises to videos to show
                            videosToShow.append(workout)
                            videosToShow.append(contentsOf: exercises)
                        }
                    }
                }
            }
            
            // Create complete workout plan with all workouts
            let completeWorkoutPlan = WorkoutPlan(
                id: workoutPlan.id,
                title: workoutPlan.title,
                description: workoutPlan.description,
                instructorId: workoutPlan.instructorId,
                videoUrl: workoutPlan.videoUrl,
                thumbnailUrl: workoutPlan.thumbnailUrl,
                difficulty: workoutPlan.difficulty,
                targetMuscles: workoutPlan.targetMuscles,
                workouts: workoutsWithMetadata,
                duration: workoutPlan.duration,
                createdAt: workoutPlan.createdAt,
                updatedAt: workoutPlan.updatedAt
            )
            videosToShow.insert(completeWorkoutPlan, at: 0)
            
        default:
            print("🎬 Unknown video type: \(type)")
        }
        
        return videosToShow
    }

    private func loadMoreVideos() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            // Use the last few video IDs to get recommendations
            let videoIds = videos.suffix(4).compactMap { $0.first?.id }
            print("🎬 Getting recommendations based on: \(videoIds)")

            let newRecommendations = try await recommendationService.getRecommendations(
                forVideos: videoIds
            )

            // Fetch each recommended video from Firestore
            let db = Firestore.firestore()
            var newVideoLists: [[any VideoContent]] = []

            for recommendation in newRecommendations {
                do {
                    let doc = try await db.collection("videos").document(recommendation.videoId).getDocument()
                    let videosToShow = try await handleVideoDocument(doc, db: db)
                    
                    // Create individual lists for each video
                    for video in videosToShow {
                        newVideoLists.append([video])
                    }
                } catch {
                    print("❌ Error fetching video: \(error)")
                    continue
                }
            }

            print("🎬 Loaded \(newVideoLists.count) new video lists")
            await MainActor.run {
                videos.append(contentsOf: newVideoLists)
            }

        } catch {
            print("❌ Error loading more videos: \(error)")
        }
    }
}

#Preview {
    VideoFeedView(initialVideos: [], startingAt: 0)
}
