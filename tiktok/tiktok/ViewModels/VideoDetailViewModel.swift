import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class VideoDetailViewModel: ObservableObject {
  @Published var isLiked = false
  @Published var isLoading = false
  @Published var error: String?
  @Published var instructorName: String = ""

  private let db = Firestore.firestore()
  let videoId: String
  private var likeDocument: DocumentReference?
  private let auth = Auth.auth()

  init(videoId: String) {
    self.videoId = videoId
    Task {
      await checkIfLiked()
      await fetchInstructorName()
    }
  }

  private func fetchInstructorName() async {
    do {
      // First get the video to get the instructorId
      let videoDoc = try await db.collection("videos").document(videoId).getDocument()
      guard let instructorId = videoDoc.data()?["instructorId"] as? String else { return }

      // Then fetch the instructor's user document
      let userDoc = try await db.collection("users").document(instructorId).getDocument()
      if let displayName = userDoc.data()?["displayName"] as? String {
        self.instructorName = displayName
      }
    } catch {
      self.error = "Failed to fetch instructor details: \(error.localizedDescription)"
    }
  }

  private func checkIfLiked() async {
    guard let userId = Auth.auth().currentUser?.uid else { return }

    do {
      let snapshot = try await db.collection("likes")
        .whereField("userId", isEqualTo: userId)
        .whereField("videoId", isEqualTo: videoId)
        .getDocuments()

      if let doc = snapshot.documents.first {
        likeDocument = doc.reference
        isLiked = true
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func toggleLike() async {
    guard let userId = Auth.auth().currentUser?.uid else {
      error = "Please sign in to like videos"
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      if isLiked {
        // Unlike
        if let likeDoc = likeDocument {
          try await likeDoc.delete()
          isLiked = false
          likeDocument = nil
        }
      } else {
        // Like
        let newLike =
          [
            "userId": userId,
            "videoId": videoId,
            "createdAt": Timestamp(),
          ] as [String: Any]

        let docRef = try await db.collection("likes").addDocument(data: newLike)
        likeDocument = docRef
        isLiked = true
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}
