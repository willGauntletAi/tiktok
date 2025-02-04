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
        }
      } else {
        self?.currentUser = nil
      }
    }
  }

  private func fetchUser(authUser: FirebaseAuth.User) async throws {
    let snapshot = try await db.collection("users").document(authUser.uid).getDocument()
    if let userData = try? snapshot.data(as: User.self) {
      self.currentUser = userData
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
      self.currentUser = user
    } else if let existingUser = try? userDoc.data(as: User.self) {
      self.currentUser = existingUser
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

  func signOut() throws {
    try Auth.auth().signOut()
    self.currentUser = nil
    self.isAuthenticated = false
  }
}
