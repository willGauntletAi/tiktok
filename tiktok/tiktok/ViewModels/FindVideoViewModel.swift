import FirebaseAuth
import FirebaseFirestore
import Foundation

protocol EmptyInitializable {
    static func empty() -> Self
}

extension Exercise: EmptyInitializable {}
extension Workout: EmptyInitializable {}

@MainActor
class FindVideoViewModel<T: VideoContent>: ObservableObject {
    @Published var instructorEmail = ""
    @Published var searchText = ""
    @Published var items: [T] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var emailSuggestions: [String] = []
    @Published var isEmailFocused = false

    var selectedIds: Set<String> = []
    private let db = Firestore.firestore()
    private let type: String

    init(type: String) {
        self.type = type
    }

    func searchEmails() async {
        guard !instructorEmail.isEmpty else {
            emailSuggestions = []
            return
        }

        do {
            let snapshot = try await db.collection("users")
                .whereField("email", isGreaterThanOrEqualTo: instructorEmail)
                .whereField("email", isLessThan: instructorEmail + "z")
                .getDocuments()

            emailSuggestions = snapshot.documents.compactMap { doc in
                doc.data()["email"] as? String
            }
        } catch {
            print("Error searching emails: \(error)")
            emailSuggestions = []
        }
    }

    func selectEmail(_ email: String) async {
        instructorEmail = email
        emailSuggestions = []
        isEmailFocused = false
        await search()
    }

    func parseExercise(doc: DocumentSnapshot) -> T {
        let data = doc.data()!
        return Exercise(
            id: doc.documentID,
            type: data["type"] as? String ?? "",
            title: data["title"] as? String ?? "",
            description: data["description"] as? String ?? "",
            instructorId: data["instructorId"] as? String ?? "",
            videoUrl: data["videoUrl"] as? String ?? "",
            thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
            difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner")
                ?? .beginner,
            targetMuscles: data["targetMuscles"] as? [String] ?? [],
            duration: data["duration"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        ) as! T
    }

    func parseWorkout(doc: DocumentSnapshot) -> T {
        let data = doc.data()!
        let id = doc.documentID
        let title = data["title"] as? String ?? ""
        let description = data["description"] as? String ?? ""
        let instructorId = data["instructorId"] as? String ?? ""
        let videoUrl = data["videoUrl"] as? String ?? ""
        let thumbnailUrl = data["thumbnailUrl"] as? String ?? ""
        let difficulty = Difficulty(rawValue: data["difficulty"] as? String ?? "beginner") ?? .beginner
        let targetMuscles = data["targetMuscles"] as? [String] ?? []
        let totalDuration = data["totalDuration"] as? Int ?? 0
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        // Convert exercise references to Exercise objects
        var exercises: [Exercise] = []
        if let exerciseRefs = data["exercises"] as? [[String: Any]] {
            exercises = exerciseRefs.compactMap { exerciseData in
                guard let id = exerciseData["id"] as? String else { return nil }
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
        }

        return Workout(
            id: id,
            title: title,
            description: description,
            exercises: exercises,
            instructorId: instructorId,
            videoUrl: videoUrl,
            thumbnailUrl: thumbnailUrl,
            difficulty: difficulty,
            targetMuscles: targetMuscles,
            totalDuration: totalDuration,
            createdAt: createdAt,
            updatedAt: updatedAt
        ) as! T
    }

    func search() async {
        isLoading = true
        errorMessage = nil

        do {
            var query = db.collection("videos")
                .whereField("type", isEqualTo: type.lowercased())

            if !instructorEmail.isEmpty {
                let userSnapshot = try await db.collection("users")
                    .whereField("email", isEqualTo: instructorEmail)
                    .getDocuments()

                if let userId = userSnapshot.documents.first?.documentID {
                    query = query.whereField("instructorId", isEqualTo: userId)
                }
            }

            if !searchText.isEmpty {
                query = query.whereField("title", isGreaterThanOrEqualTo: searchText)
                    .whereField("title", isLessThan: searchText + "z")
            }

            let snapshot = try await query.getDocuments()

            items = snapshot.documents.compactMap { doc in
                var video: T?
                if type == "exercise" {
                    video = parseExercise(doc: doc)
                } else {
                    video = parseWorkout(doc: doc)
                }
                return video
            }
        } catch {
            errorMessage = "Failed to search \(type.lowercased())s: \(error.localizedDescription)"
            items = []
        }

        isLoading = false
    }
}
