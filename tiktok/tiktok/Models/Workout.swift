import FirebaseFirestore
import Foundation

struct Workout: Identifiable {
    var id: String
    var title: String
    var description: String
    var exercises: [Exercise]
    var instructorId: String
    var videoUrl: String
    var thumbnailUrl: String
    var difficulty: String
    var targetMuscles: [String]
    var totalDuration: Int
    var type: String
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
        difficulty: String,
        targetMuscles: [String],
        totalDuration: Int,
        type: String,
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
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(document: DocumentSnapshot) {
        self.id = document.documentID
        let data = document.data() ?? [:]
        self.title = data["title"] as? String ?? ""
        self.description = data["description"] as? String ?? ""
        self.instructorId = data["instructorId"] as? String ?? ""
        self.videoUrl = data["videoUrl"] as? String ?? ""
        self.thumbnailUrl = data["thumbnailUrl"] as? String ?? ""
        self.difficulty = data["difficulty"] as? String ?? "beginner"
        self.targetMuscles = data["targetMuscles"] as? [String] ?? []
        self.totalDuration = data["totalDuration"] as? Int ?? 0
        self.type = data["type"] as? String ?? "workout"
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        // Convert exercise references to Exercise objects
        if let exerciseRefs = data["exercises"] as? [[String: Any]] {
            self.exercises = exerciseRefs.compactMap { exerciseData in
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
                    difficulty: Difficulty(rawValue: exerciseData["difficulty"] as? String ?? "beginner") ?? .beginner,
                    targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
                    duration: exerciseData["duration"] as? Int ?? 0,
                    sets: exerciseData["sets"] as? Int,
                    reps: exerciseData["reps"] as? Int,
                    createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } else {
            self.exercises = []
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
            difficulty: "beginner",
            targetMuscles: [],
            totalDuration: 0,
            type: "workout",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    var dictionary: [String: Any] {
        [
            "id": id,
            "type": type,
            "title": title,
            "description": description,
            "instructorId": instructorId,
            "videoUrl": videoUrl,
            "thumbnailUrl": thumbnailUrl,
            "difficulty": difficulty,
            "targetMuscles": targetMuscles,
            "exercises": exercises.map { $0.id },
            "totalDuration": totalDuration,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
}
