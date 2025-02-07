import SwiftUI
import FirebaseFirestore

struct VideoGridView: View {
    let videos: [ProfileViewModel.Video]
    @EnvironmentObject private var navigator: Navigator
    private let db = Firestore.firestore()

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(videos) { video in
                    VideoThumbnailView(video: video)
                        .frame(height: UIScreen.main.bounds.width / 3)
                        .onTapGesture {
                            print("🎬 VideoGridView: Tapped video with ID: \(video.id), title: \(video.title)")
                            Task {
                                await handleVideoTap(video)
                            }
                        }
                }
            }
            .padding(.horizontal, 1)
        }
    }
    
    private func handleVideoTap(_ video: ProfileViewModel.Video) async {
        do {
            var videosToShow: [any VideoContent] = []
            
            switch video.type {
            case .workoutPlan:
                // Fetch the complete workout plan with its workouts and exercises
                let planDoc = try await db.collection("videos").document(video.id).getDocument()
                if let planData = planDoc.data() {
                    let plan = WorkoutPlan(
                        id: video.id,
                        title: video.title,
                        description: video.description,
                        instructorId: video.instructorId,
                        videoUrl: video.videoUrl,
                        thumbnailUrl: video.thumbnailUrl,
                        difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                        targetMuscles: video.targetMuscles,
                        workouts: [], // We'll fetch workouts next
                        duration: planData["duration"] as? Int ?? 7,
                        createdAt: video.createdAt,
                        updatedAt: video.updatedAt
                    )
                    
                    // Add the plan itself first
                    videosToShow.append(plan)
                    
                    // Fetch and add workouts and their exercises
                    if let workoutDicts = planData["workouts"] as? [[String: Any]] {
                        for workoutDict in workoutDicts {
                            if let workoutId = workoutDict["id"] as? String {
                                let workoutDoc = try await db.collection("videos").document(workoutId).getDocument()
                                if let workoutData = workoutDoc.data() {
                                    // Create workout
                                    let workout = Workout(
                                        id: workoutId,
                                        title: workoutData["title"] as? String ?? "",
                                        description: workoutData["description"] as? String ?? "",
                                        exercises: [], // We'll add these next
                                        instructorId: workoutData["instructorId"] as? String ?? "",
                                        videoUrl: workoutData["videoUrl"] as? String ?? "",
                                        thumbnailUrl: workoutData["thumbnailUrl"] as? String ?? "",
                                        difficulty: Difficulty(rawValue: workoutData["difficulty"] as? String ?? "") ?? .beginner,
                                        targetMuscles: workoutData["targetMuscles"] as? [String] ?? [],
                                        totalDuration: workoutData["totalDuration"] as? Int ?? 0,
                                        createdAt: (workoutData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                        updatedAt: (workoutData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                                    )
                                    videosToShow.append(workout)
                                    
                                    // Add workout's exercises
                                    if let exerciseDicts = workoutData["exercises"] as? [[String: Any]] {
                                        for exerciseDict in exerciseDicts {
                                            if let exerciseId = exerciseDict["id"] as? String {
                                                let exerciseDoc = try await db.collection("videos").document(exerciseId).getDocument()
                                                if let exerciseData = exerciseDoc.data() {
                                                    let exercise = Exercise(
                                                        id: exerciseId,
                                                        type: exerciseData["type"] as? String ?? "exercise",
                                                        title: exerciseData["title"] as? String ?? "",
                                                        description: exerciseData["description"] as? String ?? "",
                                                        instructorId: exerciseData["instructorId"] as? String ?? "",
                                                        videoUrl: exerciseData["videoUrl"] as? String ?? "",
                                                        thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
                                                        difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "") ?? .beginner,
                                                        targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                                                        duration: exerciseData["duration"] as? Int ?? 0,
                                                        createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                                        updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                                                    )
                                                    videosToShow.append(exercise)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
            case .workout:
                // Fetch the complete workout with its exercises
                let workoutDoc = try await db.collection("videos").document(video.id).getDocument()
                if let workoutData = workoutDoc.data() {
                    let workout = Workout(
                        id: video.id,
                        title: workoutData["title"] as? String ?? "",
                        description: workoutData["description"] as? String ?? "",
                        exercises: [], // We'll add these next
                        instructorId: workoutData["instructorId"] as? String ?? "",
                        videoUrl: workoutData["videoUrl"] as? String ?? "",
                        thumbnailUrl: workoutData["thumbnailUrl"] as? String ?? "",
                        difficulty: Difficulty(rawValue: workoutData["difficulty"] as? String ?? "") ?? .beginner,
                        targetMuscles: workoutData["targetMuscles"] as? [String] ?? [],
                        totalDuration: workoutData["totalDuration"] as? Int ?? 0,
                        createdAt: (workoutData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (workoutData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                    videosToShow.append(workout)
                    
                    // Fetch and add exercises
                    if let exerciseDicts = workoutData["exercises"] as? [[String: Any]] {
                        for exerciseDict in exerciseDicts {
                            if let exerciseId = exerciseDict["id"] as? String {
                                let exerciseDoc = try await db.collection("videos").document(exerciseId).getDocument()
                                if let exerciseData = exerciseDoc.data() {
                                    let exercise = Exercise(
                                        id: exerciseId,
                                        type: exerciseData["type"] as? String ?? "exercise",
                                        title: exerciseData["title"] as? String ?? "",
                                        description: exerciseData["description"] as? String ?? "",
                                        instructorId: exerciseData["instructorId"] as? String ?? "",
                                        videoUrl: exerciseData["videoUrl"] as? String ?? "",
                                        thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
                                        difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "") ?? .beginner,
                                        targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                                        duration: exerciseData["duration"] as? Int ?? 0,
                                        createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                                        updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                                    )
                                    videosToShow.append(exercise)
                                }
                            }
                        }
                    }
                }
                
            case .exercise:
                // For exercises, just create and add the exercise itself
                let exercise = Exercise(
                    id: video.id,
                    type: video.type.rawValue,
                    title: video.title,
                    description: video.description,
                    instructorId: video.instructorId,
                    videoUrl: video.videoUrl,
                    thumbnailUrl: video.thumbnailUrl,
                    difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                    targetMuscles: video.targetMuscles,
                    duration: 0,
                    createdAt: video.createdAt,
                    updatedAt: video.updatedAt
                )
                videosToShow.append(exercise)
            }
            
            print("🎬 VideoGridView: Navigating to video detail with \(videosToShow.count) videos")
            videosToShow.enumerated().forEach { index, video in
                print("  [\(index)] \(video.id): \(video.title)")
            }
            
            await MainActor.run {
                navigator.navigate(to: .videoDetail(videos: videosToShow, startIndex: 0))
            }
            
        } catch {
            print("❌ Error fetching video content: \(error)")
        }
    }
}
