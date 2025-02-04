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

  private let db = Firestore.firestore()

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

    guard let currentUser = Auth.auth().currentUser else {
      error = "No user logged in"
      isLoading = false
      return
    }

    do {
      let userDoc = try await db.collection("users").document(currentUser.uid).getDocument()
      if let userData = userDoc.data() {
        user = User(
          id: currentUser.uid,
          email: userData["email"] as? String ?? "",
          displayName: userData["displayName"] as? String ?? "",
          createdAt: (userData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
          updatedAt: (userData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
      }

      // Fetch user's created videos
      let videosQuery = db.collection("videos")
        .whereField("instructorId", isEqualTo: currentUser.uid)
      let videosDocs = try await videosQuery.getDocuments()
      userVideos = videosDocs.documents.compactMap { doc in
        createVideoFromDoc(doc)
      }

      // Fetch user's liked videos
      let likesQuery = db.collection("likes")
        .whereField("userId", isEqualTo: currentUser.uid)
      let likesDocs = try await likesQuery.getDocuments()
      let videoIds = likesDocs.documents.compactMap { $0.data()["videoId"] as? String }

      // Fetch the actual videos that were liked
      likedVideos = []
      for videoId in videoIds {
        if let videoDoc = try? await db.collection("videos").document(videoId).getDocument(),
          let video = createVideoFromDoc(videoDoc)
        {
          likedVideos.append(video)
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
    do {
      try Auth.auth().signOut()
      // Clear user data after logout
      user = nil
      userVideos = []
      likedVideos = []
    } catch {
      self.error = error.localizedDescription
    }
  }
}
