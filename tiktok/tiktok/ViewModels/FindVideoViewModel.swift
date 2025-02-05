import FirebaseAuth
import FirebaseFirestore
import Foundation

protocol EmptyInitializable {
  static func empty() -> Self
}

extension Exercise: EmptyInitializable {}
extension Workout: EmptyInitializable {}

@MainActor
class FindVideoViewModel<T: Identifiable & EmptyInitializable>: ObservableObject {
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

  func selectEmail(_ email: String) {
    instructorEmail = email
    emailSuggestions = []
    isEmailFocused = false
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
        let data = doc.data()
        if type == "Exercise" {
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
          ) as? T ?? T.empty()
        } else {
          return Workout(
            id: doc.documentID,
            title: data["title"] as? String ?? "",
            description: data["description"] as? String ?? "",
            exercises: [],
            instructorId: data["instructorId"] as? String ?? "",
            videoUrl: data["videoUrl"] as? String ?? "",
            thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
            difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "beginner")
              ?? .beginner,
            targetMuscles: data["targetMuscles"] as? [String] ?? [],
            totalDuration: data["totalDuration"] as? Int ?? 0,
            type: data["type"] as? String ?? "workout",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
          ) as? T ?? T.empty()
        }
      }
    } catch {
      errorMessage = "Failed to search \(type.lowercased())s: \(error.localizedDescription)"
      items = []
    }

    isLoading = false
  }
}
