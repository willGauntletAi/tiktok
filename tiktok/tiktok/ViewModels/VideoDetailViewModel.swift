import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class VideoDetailViewModel: ObservableObject {
  @Published var isLiked = false
  @Published var isLoading = false
  @Published var error: String?

  private let db = Firestore.firestore()
  private let videoId: String
  private var likeDocument: DocumentReference?

  init(videoId: String) {
    self.videoId = videoId
    Task {
      await checkIfLiked()
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
