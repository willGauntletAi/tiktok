import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct VideoRecommendation: Hashable {
    let videoId: String
    let isOriginal: Bool
    let video: WorkoutPlan?

    func hash(into hasher: inout Hasher) {
        hasher.combine(videoId)
        hasher.combine(isOriginal)
        hasher.combine(video?.id)
    }

    static func == (lhs: VideoRecommendation, rhs: VideoRecommendation) -> Bool {
        lhs.videoId == rhs.videoId && lhs.isOriginal == rhs.isOriginal && lhs.video?.id == rhs.video?.id
    }
}

class RecommendationService {
    private let functions = Functions.functions()

    func getRecommendations(forVideos videoIds: [String] = []) async throws -> [VideoRecommendation] {
        print("🎯 Getting recommendations for videoIds: \(videoIds)")
        let data = ["videoIds": videoIds]

        print("🎯 Calling Firebase function...")
        let result = try await functions.httpsCallable("getRecommendations").call(data)
        print("🎯 Firebase function returned result")

        guard let response = result.data as? [String: Any] else {
            print("❌ Failed to cast response.data to [String: Any]")
            throw NSError(
                domain: "RecommendationService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        guard let recommendations = response["recommendations"] as? [[String: Any]] else {
            print("❌ Failed to cast response[recommendations] to [[String: Any]]")
            throw NSError(
                domain: "RecommendationService", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
            )
        }

        print("🎯 Processing \(recommendations.count) recommendations")
        let mappedRecommendations = recommendations.map { recommendation in
            let videoId = recommendation["videoId"] as? String ?? ""
            let isOriginal = recommendation["isOriginal"] as? Bool ?? false
            var video: WorkoutPlan?

            if let videoData = recommendation["video"] as? [String: Any] {
                print("🎯 Processing video data for videoId: \(videoId)")
                let exercise = Exercise(
                    id: videoData["id"] as? String ?? "",
                    type: videoData["type"] as? String ?? "",
                    title: videoData["title"] as? String ?? "",
                    description: videoData["description"] as? String ?? "",
                    instructorId: videoData["instructorId"] as? String ?? "",
                    videoUrl: videoData["videoUrl"] as? String ?? "",
                    thumbnailUrl: videoData["thumbnailUrl"] as? String ?? "",
                    difficulty: Difficulty(rawValue: videoData["difficulty"] as? String ?? "") ?? .beginner,
                    targetMuscles: videoData["targetMuscles"] as? [String] ?? [],
                    duration: 0,
                    createdAt: (videoData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (videoData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )

                let workout = Workout(
                    id: UUID().uuidString,
                    title: exercise.title,
                    description: exercise.description,
                    exercises: [exercise],
                    instructorId: exercise.instructorId,
                    videoUrl: exercise.videoUrl,
                    thumbnailUrl: exercise.thumbnailUrl,
                    difficulty: exercise.difficulty,
                    targetMuscles: exercise.targetMuscles,
                    totalDuration: exercise.duration,
                    createdAt: exercise.createdAt,
                    updatedAt: exercise.updatedAt
                )

                video = WorkoutPlan(
                    id: videoData["id"] as? String ?? "",
                    title: videoData["title"] as? String ?? "",
                    description: videoData["description"] as? String ?? "",
                    instructorId: videoData["instructorId"] as? String ?? "",
                    videoUrl: videoData["videoUrl"] as? String ?? "",
                    thumbnailUrl: videoData["thumbnailUrl"] as? String ?? "",
                    difficulty: Difficulty(rawValue: videoData["difficulty"] as? String ?? "") ?? .beginner,
                    targetMuscles: videoData["targetMuscles"] as? [String] ?? [],
                    workouts: [
                        WorkoutWithMetadata(
                            workout: workout,
                            weekNumber: 1,
                            dayOfWeek: 1
                        ),
                    ],
                    duration: 7,
                    createdAt: (videoData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (videoData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                print("🎯 Successfully created WorkoutPlan for videoId: \(videoId)")
            } else {
                print("⚠️ No video data found for videoId: \(videoId)")
            }

            return VideoRecommendation(videoId: videoId, isOriginal: isOriginal, video: video)
        }

        print("🎯 Returning \(mappedRecommendations.count) recommendations")
        return mappedRecommendations
    }
}
