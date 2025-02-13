import AVKit
import FirebaseFirestore
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
    let initialVideos: [[any VideoContent]]
    let startingAt: Int
    @State private var videos: [[any VideoContent]]
    @State private var currentIndex: Int?
    @State private var visibleVideoId: String?
    @EnvironmentObject private var navigator: Navigator
    @State private var isLoading = false
    private let recommendationService = RecommendationService()

    init(initialVideos: [[any VideoContent]], startingAt: Int = 0) {
        self.initialVideos = initialVideos
        self.startingAt = startingAt
        _videos = State(initialValue: initialVideos)
        _currentIndex = State(initialValue: startingAt)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(0 ..< videos.count, id: \.self) { index in
                        VideoDetailView(
                            videos: videos[index],
                            startAt: 0,
                            showBackButton: true,
                            onBack: {
                                print("🎬 Back button tapped")
                                withAnimation {
                                    navigator.pop()
                                }
                            }
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                        .onAppear {
                            print("🎬 Video at index \(index) appeared")
                            visibleVideoId = videos[index].first?.id
                            if index >= videos.count - 2 && !isLoading {
                                Task {
                                    await loadMoreVideos()
                                }
                            }
                        }
                        .onDisappear {
                            if visibleVideoId == videos[index].first?.id {
                                visibleVideoId = nil
                            }
                        }
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)
            .onChange(of: currentIndex) { _, newValue in
                if let index = newValue {
                    print("🎬 Scrolled to index: \(index)")
                    visibleVideoId = videos[index].first?.id
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
                        withAnimation {
                            navigator.pop()
                        }
                    }
                }
        )
        .onAppear {
            print("🎬 VideoFeedView appeared with \(videos.count) videos")
            if videos.isEmpty {
                Task {
                    await loadMoreVideos()
                }
            } else {
                visibleVideoId = videos[startingAt].first?.id
            }
        }
        .onDisappear {
            visibleVideoId = nil
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
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        print("🎬 Getting recommendations based on: \(videos.last?.map { $0.id } ?? [])")

        do {
            let recommendations = try await recommendationService.getRecommendations(
                forVideos: videos.last?.map { $0.id } ?? []
            )

            // Process each recommendation
            let db = Firestore.firestore()
            var newVideoLists: [[any VideoContent]] = []

            for recommendation in recommendations {
                do {
                    let doc = try await db.collection("videos").document(recommendation.videoId).getDocument()
                    let videosToShow = try await handleVideoDocument(doc, db: db)
                    if !videosToShow.isEmpty {
                        newVideoLists.append(videosToShow)
                    }
                } catch {
                    print("❌ Error processing video recommendation: \(error)")
                }
            }

            await MainActor.run {
                if !newVideoLists.isEmpty {
                    videos.append(contentsOf: newVideoLists)
                }
            }
        } catch {
            print("❌ Error loading more videos: \(error)")
        }
    }
}

#Preview {
    VideoFeedView(initialVideos: [], startingAt: 0)
}
