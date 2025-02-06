import FirebaseFirestore
import Foundation

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let displayName: String
    let createdAt: Date
    let updatedAt: Date

    var dictionary: [String: Any] {
        [
            "id": id,
            "email": email,
            "displayName": displayName,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
        ]
    }
}
