import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
  @Published var user: User?
  @Published var userVideos: [Video] = []
  @Published var likedVideos: [Video] = []
  @Published var isLoading = false
  @Published var error: String?
  let userId: String?  // nil means current user

  private let db = Firestore.firestore()
  private let auth = Auth.auth()

  init(userId: String? = nil) {
    self.userId = userId
  }

  struct User {
    let id: String
    let email: String
    let displayName: String
    let createdAt: Date
    let updatedAt: Date
  }

  struct Video: Identifiable {
    let id: String
    let type: VideoType
    let title: String
    let description: String
    let instructorId: String
    let videoUrl: String
    let thumbnailUrl: String
    let difficulty: Difficulty
    let targetMuscles: [String]
    let createdAt: Date
    let updatedAt: Date
  }

  enum VideoType: String {
    case exercise
    case workout
    case workoutPlan
  }

  enum Difficulty: String {
    case beginner
    case intermediate
    case advanced
  }

  func fetchUserProfile() async {
    isLoading = true
    error = nil

    do {
      let targetUserId = userId ?? auth.currentUser?.uid
      guard let targetUserId = targetUserId else {
        error = "No authenticated user"
        isLoading = false
        return
      }

      // Fetch user data
      let userDoc = try await db.collection("users").document(targetUserId).getDocument()
      guard let userData = userDoc.data() else {
        error = "User data not found"
        isLoading = false
        return
      }

      // Create user object
      user = User(
        id: userDoc.documentID,
        email: userData["email"] as? String ?? "",
        displayName: userData["displayName"] as? String ?? "",
        createdAt: (userData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
        updatedAt: (userData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
      )

      // Fetch user's videos
      let videosQuery = db.collection("videos")
        .whereField("instructorId", isEqualTo: targetUserId)
        .order(by: "createdAt", descending: true)

      let videosDocs = try await videosQuery.getDocuments()
      userVideos = videosDocs.documents.compactMap { doc in
        createVideoFromDoc(doc)
      }

      // Fetch liked videos only for current user
      if userId == nil {
        let likedVideosQuery = db.collection("likes")
          .whereField("userId", isEqualTo: targetUserId)
          .order(by: "createdAt", descending: true)

        let likedDocs = try await likedVideosQuery.getDocuments()
        let videoIds = likedDocs.documents.compactMap { $0.data()["videoId"] as? String }

        // Fetch the actual video documents
        likedVideos = []
        for videoId in videoIds {
          if let doc = try? await db.collection("videos").document(videoId).getDocument(),
            let data = doc.data()
          {
            if let video = createVideoFromDoc(doc) {
              likedVideos.append(video)
            }
          }
        }
      }

    } catch {
      self.error = error.localizedDescription
    }

    isLoading = false
  }

  private func createVideoFromDoc(_ doc: DocumentSnapshot) -> Video? {
    guard let data = doc.data() else { return nil }
    return Video(
      id: doc.documentID,
      type: VideoType(rawValue: data["type"] as? String ?? "") ?? .exercise,
      title: data["title"] as? String ?? "",
      description: data["description"] as? String ?? "",
      instructorId: data["instructorId"] as? String ?? "",
      videoUrl: data["videoUrl"] as? String ?? "",
      thumbnailUrl: data["thumbnailUrl"] as? String ?? "",
      difficulty: Difficulty(rawValue: data["difficulty"] as? String ?? "") ?? .beginner,
      targetMuscles: data["targetMuscles"] as? [String] ?? [],
      createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
      updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
    )
  }

  func signOut() {
    guard userId == nil else { return }  // Only allow sign out from current user's profile
    do {
      try auth.signOut()
      // Clear user data after logout
      user = nil
      userVideos = []
      likedVideos = []
    } catch {
      self.error = error.localizedDescription
    }
  }
}
