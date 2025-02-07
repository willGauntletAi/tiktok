import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var userVideos: [Video] = []
    @Published var likedVideos: [Video] = []
    @Published var isLoading = false
    @Published var isSigningOut = false
    @Published var error: String?
    let userId: String? // nil means current user

    private let db = Firestore.firestore()
    private let auth = Auth.auth()

    init(userId: String? = nil) {
        print("🎬 ProfileViewModel: Initializing with userId: \(userId ?? "nil (current user)")")
        self.userId = userId
        
        // If we're showing the current user's profile, verify auth state
        if userId == nil {
            if let currentUserId = Auth.auth().currentUser?.uid {
                print("🎬 ProfileViewModel: Current user is authenticated: \(currentUserId)")
            } else {
                print("❌ ProfileViewModel: No authenticated user when trying to show current user's profile")
            }
        }
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

    @MainActor
    func fetchUserProfile() async {
        print("🎬 ProfileViewModel: Starting fetch with userId: \(userId ?? "nil (current user)")")
        print("🎬 ProfileViewModel: Current auth user ID: \(auth.currentUser?.uid ?? "no auth user")")
        
        isLoading = true
        error = nil

        do {
            let targetUserId = userId ?? auth.currentUser?.uid
            guard let targetUserId = targetUserId else {
                error = "No authenticated user"
                print("❌ ProfileViewModel: No authenticated user found")
                isLoading = false
                return
            }

            print("🎬 ProfileViewModel: Fetching data for user: \(targetUserId)")

            // Fetch user data
            let userDoc = try await db.collection("users").document(targetUserId).getDocument()
            guard let userData = userDoc.data() else {
                error = "User data not found"
                print("❌ ProfileViewModel: No user data found for ID: \(targetUserId)")
                isLoading = false
                return
            }

            print("✅ ProfileViewModel: Found user data")

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
            print("🎬 ProfileViewModel: Found \(videosDocs.documents.count) videos")
            
            userVideos = videosDocs.documents.compactMap { doc in
                createVideoFromDoc(doc)
            }
            print("🎬 ProfileViewModel: Processed \(userVideos.count) user videos")

            // Fetch liked videos only for current user
            if userId == nil {
                let likedVideosQuery = db.collection("likes")
                    .whereField("userId", isEqualTo: targetUserId)
                    .order(by: "createdAt", descending: true)

                let likedDocs = try await likedVideosQuery.getDocuments()
                let videoIds = likedDocs.documents.compactMap { $0.data()["videoId"] as? String }
                print("🎬 ProfileViewModel: Found \(videoIds.count) liked video IDs: \(videoIds)")

                // Fetch the actual video documents
                likedVideos = []
                for videoId in videoIds {
                    print("🎬 ProfileViewModel: Fetching liked video: \(videoId)")
                    do {
                        let doc = try await db.collection("videos").document(videoId).getDocument()
                        if doc.exists {
                            if let video = createVideoFromDoc(doc) {
                                likedVideos.append(video)
                                print("✅ ProfileViewModel: Successfully added liked video: \(videoId)")
                            } else {
                                print("❌ ProfileViewModel: Failed to create video object for: \(videoId)")
                            }
                        } else {
                            print("❌ ProfileViewModel: Liked video document doesn't exist: \(videoId)")
                            // Optionally clean up the orphaned like
                            try? await cleanupOrphanedLike(videoId: videoId, userId: targetUserId)
                        }
                    } catch {
                        print("❌ ProfileViewModel: Error fetching liked video \(videoId): \(error.localizedDescription)")
                    }
                }
                print("🎬 ProfileViewModel: Processed \(likedVideos.count) liked videos")
            }

        } catch {
            self.error = error.localizedDescription
            print("❌ ProfileViewModel: Error fetching data: \(error.localizedDescription)")
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

    private func cleanupOrphanedLike(videoId: String, userId: String) async throws {
        print("🧹 ProfileViewModel: Cleaning up orphaned like for video: \(videoId)")
        // Find and delete the orphaned like document
        let likeDocs = try await db.collection("likes")
            .whereField("userId", isEqualTo: userId)
            .whereField("videoId", isEqualTo: videoId)
            .getDocuments()
        
        for doc in likeDocs.documents {
            try await doc.reference.delete()
            print("✅ ProfileViewModel: Deleted orphaned like document: \(doc.documentID)")
        }
    }

    @MainActor
    func signOut() {
        Task {
            isSigningOut = true
            do {
                try await auth.signOut()
                // Clear user data after logout
                user = nil
                userVideos = []
                likedVideos = []
            } catch {
                self.error = error.localizedDescription
                print("Error signing out: \(error)")
            }
            isSigningOut = false
        }
    }
}
