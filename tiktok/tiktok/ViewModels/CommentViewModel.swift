import FirebaseAuth
import FirebaseFirestore
import Foundation

struct Comment: Identifiable {
    let id: String
    let userId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    var userDisplayName: String = ""
}

@MainActor
class CommentViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var newCommentText = ""

    private let videoId: String
    private let db = Firestore.firestore()
    private let auth = Auth.auth()

    init(videoId: String) {
        self.videoId = videoId
    }

    func fetchComments() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db.collection("comments")
                .whereField("videoId", isEqualTo: videoId)
                .order(by: "createdAt", descending: true)
                .getDocuments()

            var newComments: [Comment] = []

            for doc in snapshot.documents {
                let data = doc.data()
                guard let userId = data["userId"] as? String,
                      let content = data["content"] as? String,
                      let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
                      let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                else { continue }

                var comment = Comment(
                    id: doc.documentID,
                    userId: userId,
                    content: content,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )

                // Fetch user display name
                if let userDoc = try? await db.collection("users").document(userId).getDocument(),
                   let displayName = userDoc.data()?["displayName"] as? String
                {
                    comment.userDisplayName = displayName
                }

                newComments.append(comment)
            }

            comments = newComments

        } catch {
            self.error = error.localizedDescription
        }
    }

    func postComment() async {
        guard !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let userId = auth.currentUser?.uid else {
            error = "Please sign in to comment"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let comment =
                [
                    "videoId": videoId,
                    "userId": userId,
                    "content": newCommentText.trimmingCharacters(in: .whitespacesAndNewlines),
                    "createdAt": Timestamp(),
                    "updatedAt": Timestamp(),
                ] as [String: Any]

            try await db.collection("comments").addDocument(data: comment)
            newCommentText = ""
            await fetchComments()

        } catch {
            self.error = error.localizedDescription
        }
    }
}
