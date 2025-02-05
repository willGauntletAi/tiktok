import FirebaseFirestore
import Foundation

struct WorkoutPlan: VideoContent {
  var id: String
  var type: String = "workoutPlan"
  var title: String
  var description: String
  var instructorId: String
  var videoUrl: String
  var thumbnailUrl: String
  var difficulty: Difficulty
  var targetMuscles: [String]
  var workouts: [Workout]  // Array of full Workout objects
  var duration: Int  // in days
  var createdAt: Date
  var updatedAt: Date

  init(
    id: String,
    title: String,
    description: String,
    instructorId: String,
    videoUrl: String,
    thumbnailUrl: String,
    difficulty: Difficulty,
    targetMuscles: [String],
    workouts: [Workout],
    duration: Int,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.instructorId = instructorId
    self.videoUrl = videoUrl
    self.thumbnailUrl = thumbnailUrl
    self.difficulty = difficulty
    self.targetMuscles = targetMuscles
    self.workouts = workouts
    self.duration = duration
    self.type = "workoutPlan"
    self.createdAt = createdAt
    self.updatedAt = updatedAt
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
    dict["workouts"] = workouts.map { workout in
      var workoutDict = workout.dictionary
      workoutDict["id"] = workout.id
      return workoutDict
    }
    dict["duration"] = duration
    return dict
  }

  init(document: DocumentSnapshot) {
    self.id = document.documentID
    let data = document.data() ?? [:]
    self.title = data["title"] as? String ?? ""
    self.description = data["description"] as? String ?? ""
    self.instructorId = data["instructorId"] as? String ?? ""
    self.videoUrl = data["videoUrl"] as? String ?? ""
    self.thumbnailUrl = data["thumbnailUrl"] as? String ?? ""
    self.difficulty = Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner
    self.targetMuscles = data["targetMuscles"] as? [String] ?? []
    self.duration = data["duration"] as? Int ?? 7
    self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

    // Convert workout data to Workout objects
    if let workoutDicts = data["workouts"] as? [[String: Any]] {
      self.workouts = workoutDicts.compactMap { workoutData in
        guard let id = workoutData["id"] as? String else { return nil }

        // Convert exercise data to Exercise objects
        var exercises: [Exercise] = []
        if let exerciseDicts = workoutData["exercises"] as? [[String: Any]] {
          exercises = exerciseDicts.compactMap { exerciseData in
            guard let exerciseId = exerciseData["id"] as? String else { return nil }
            return Exercise(
              id: exerciseId,
              title: exerciseData["title"] as? String ?? "",
              description: exerciseData["description"] as? String ?? "",
              instructorId: exerciseData["instructorId"] as? String ?? "",
              videoUrl: exerciseData["videoUrl"] as? String ?? "",
              thumbnailUrl: exerciseData["thumbnailUrl"] as? String ?? "",
              difficulty: Difficulty.beginner,
              targetMuscles: exerciseData["targetMuscles"] as? [String] ?? [],
              duration: exerciseData["duration"] as? Int ?? 0,
              sets: exerciseData["sets"] as? Int,
              reps: exerciseData["reps"] as? Int,
              createdAt: (exerciseData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
              updatedAt: (exerciseData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
          }
        }

        return Workout(
          id: id,
          title: workoutData["title"] as? String ?? "",
          description: workoutData["description"] as? String ?? "",
          exercises: exercises,
          instructorId: workoutData["instructorId"] as? String ?? "",
          videoUrl: workoutData["videoUrl"] as? String ?? "",
          thumbnailUrl: workoutData["thumbnailUrl"] as? String ?? "",
          difficulty: Difficulty(rawValue: workoutData["difficulty"] as? String ?? "beginner")
            ?? .beginner,
          targetMuscles: workoutData["targetMuscles"] as? [String] ?? [],
          totalDuration: workoutData["totalDuration"] as? Int ?? 0,
          createdAt: (workoutData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
          updatedAt: (workoutData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
      }
    } else {
      self.workouts = []
    }
  }

  static func empty() -> WorkoutPlan {
    WorkoutPlan(
      id: UUID().uuidString,
      title: "",
      description: "",
      instructorId: "",
      videoUrl: "",
      thumbnailUrl: "",
      difficulty: Difficulty.beginner,
      targetMuscles: [],
      workouts: [],
      duration: 7,  // Default to 7 days
      createdAt: Date(),
      updatedAt: Date()
    )
  }
}
