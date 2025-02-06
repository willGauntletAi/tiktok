import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false

    private let db = Firestore.firestore()
    static let shared = AuthService()

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, authUser in
            self?.isAuthenticated = authUser != nil
            if let authUser = authUser {
                Task {
                    try? await self?.fetchUser(authUser: authUser)
                    // Update FCM token when user signs in
                    NotificationManager.shared.updateFCMToken(for: authUser.uid)
                }
            } else {
                self?.currentUser = nil
            }
        }
    }

    private func fetchUser(authUser: FirebaseAuth.User) async throws {
        let snapshot = try await db.collection("users").document(authUser.uid).getDocument()
        if let userData = try? snapshot.data(as: User.self) {
            currentUser = userData
        }
    }

    private func createUserDocument(for authUser: FirebaseAuth.User, email: String) async throws {
        // Check if user document already exists
        let userDoc = try await db.collection("users").document(authUser.uid).getDocument()

        if !userDoc.exists {
            // Create new user following the schema
            let now = Date()
            let user = User(
                id: authUser.uid,
                email: email.lowercased(),
                displayName: email.components(separatedBy: "@").first ?? "",
                createdAt: now,
                updatedAt: now
            )

            try await db.collection("users").document(authUser.uid).setData(user.dictionary)
            currentUser = user
        } else if let existingUser = try? userDoc.data(as: User.self) {
            currentUser = existingUser
        }
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        // Ensure user document exists in Firestore
        try await createUserDocument(for: result.user, email: email)
    }

    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        // Create user document in Firestore
        try await createUserDocument(for: result.user, email: email)
    }

    func signOut() async throws {
        if let userId = currentUser?.id {
            // Remove FCM token when user signs out
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete(),
            ])
        }

        try Auth.auth().signOut()
        currentUser = nil
        isAuthenticated = false
    }
}
