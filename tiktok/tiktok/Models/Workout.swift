import FirebaseFirestore
import Foundation

struct Workout: VideoContent, Hashable {
    var id: String
    var type: String = "workout"
    var title: String
    var description: String
    var exercises: [Exercise]
    var instructorId: String
    var videoUrl: String
    var thumbnailUrl: String
    var difficulty: Difficulty
    var targetMuscles: [String]
    var totalDuration: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        title: String,
        description: String,
        exercises: [Exercise],
        instructorId: String,
        videoUrl: String,
        thumbnailUrl: String,
        difficulty: Difficulty,
        targetMuscles: [String],
        totalDuration: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.exercises = exercises
        self.instructorId = instructorId
        self.videoUrl = videoUrl
        self.thumbnailUrl = thumbnailUrl
        self.difficulty = difficulty
        self.targetMuscles = targetMuscles
        self.totalDuration = totalDuration
        type = "workout"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(document: DocumentSnapshot) {
        id = document.documentID
        let data = document.data() ?? [:]
        title = data["title"] as? String ?? ""
        description = data["description"] as? String ?? ""
        instructorId = data["instructorId"] as? String ?? ""
        videoUrl = data["videoUrl"] as? String ?? ""
        thumbnailUrl = data["thumbnailUrl"] as? String ?? ""
        difficulty = Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner
        targetMuscles = data["targetMuscles"] as? [String] ?? []
        totalDuration = data["totalDuration"] as? Int ?? 0
        type = "workout"
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        // Convert exercise references to Exercise objects
        if let exerciseRefs = data["exercises"] as? [[String: Any]] {
            exercises = exerciseRefs.compactMap { exerciseData in
                guard let id = exerciseData["id"] as? String else {
                    return Exercise(
                        id: UUID().uuidString,
                        title: "",
                        description: "",
                        instructorId: "",
                        videoUrl: "",
                        thumbnailUrl: "",
                        difficulty: .beginner,
                        targetMuscles: [],
                        duration: 0,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                }
                return Exercise(
                    id: id,
                    title: exerciseData["title"] as? String ?? "",
                    description: exerciseData["description"] as? String ?? "",
                    instructorId: exerciseData["instructorId"] as? String ?? "",
                    videoUrl: exerciseData["videoUrl"] as? String ?? "",
                    thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
                    difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "beginner")
                        ?? .beginner,
                    targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                    duration: exerciseData["duration"] as? Int ?? 0,
                    sets: exerciseData["sets"] as? Int,
                    reps: exerciseData["reps"] as? Int,
                    createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } else {
            exercises = []
        }
    }

    static func empty() -> Workout {
        Workout(
            id: UUID().uuidString,
            title: "",
            description: "",
            exercises: [],
            instructorId: "",
            videoUrl: "",
            thumbnailUrl: "",
            difficulty: .beginner,
            targetMuscles: [],
            totalDuration: 0,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "type": type,
            "title": title,
            "description": description,
            "instructorId": instructorId,
            "videoUrl": videoUrl,
            "thumbnailUrl": thumbnailUrl,
            "difficulty": difficulty.rawValue,
            "targetMuscles": targetMuscles,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]
        dict["exercises"] = exercises.map { exercise in
            var exerciseDict =
                [
                    "id": exercise.id,
                    "type": exercise.type,
                    "title": exercise.title,
                    "description": exercise.description,
                    "instructorId": exercise.instructorId,
                    "videoUrl": exercise.videoUrl,
                    "thumbnailUrl": exercise.thumbnailUrl,
                    "difficulty": exercise.difficulty.rawValue,
                    "targetMuscles": exercise.targetMuscles,
                    "duration": exercise.duration,
                    "createdAt": Timestamp(date: exercise.createdAt),
                    "updatedAt": Timestamp(date: exercise.updatedAt),
                ] as [String: Any]
            if let sets = exercise.sets {
                exerciseDict["sets"] = sets
            }
            if let reps = exercise.reps {
                exerciseDict["reps"] = reps
            }
            return exerciseDict
        }
        dict["totalDuration"] = totalDuration
        return dict
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Workout, rhs: Workout) -> Bool {
        lhs.id == rhs.id
    }
}
