import FirebaseFirestore
import Foundation

@MainActor
class FindExerciseViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var searchText: String = ""
    @Published var instructorEmail: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var emailSuggestions: [String] = []
    @Published var isEmailFocused: Bool = false
    var selectedExerciseIds: Set<String> = [] // Track selected exercise IDs

    private let db = Firestore.firestore()

    func isExerciseSelected(_ exercise: Exercise) -> Bool {
        selectedExerciseIds.contains(exercise.id)
    }

    func searchEmails() async {
        guard !instructorEmail.isEmpty else {
            emailSuggestions = []
            return
        }

        do {
            let snapshot = try await db.collection("users")
                .whereField("email", isGreaterThanOrEqualTo: instructorEmail.lowercased())
                .whereField("email", isLessThan: instructorEmail.lowercased() + "\u{f8ff}")
                .limit(to: 10)
                .getDocuments()

            emailSuggestions = snapshot.documents.compactMap { document -> String? in
                document.data()["email"] as? String
            }
        } catch {
            emailSuggestions = []
        }
    }

    func selectEmail(_ email: String) {
        instructorEmail = email
        emailSuggestions = []
        isEmailFocused = false
        Task {
            await searchExercises()
        }
    }

    func searchExercises() async {
        isLoading = true
        errorMessage = nil
        emailSuggestions = []

        do {
            var instructorIds: [String] = []

            if !instructorEmail.isEmpty {
                let usersSnapshot = try await db.collection("users")
                    .whereField("email", isEqualTo: instructorEmail.lowercased())
                    .getDocuments()

                instructorIds = usersSnapshot.documents.map { $0.documentID }

                if instructorIds.isEmpty {
                    exercises = []
                    isLoading = false
                    return
                }
            }

            var query = db.collection("videos")
                .whereField("type", isEqualTo: "exercise")

            if !instructorIds.isEmpty {
                query = query.whereField("instructorId", in: instructorIds)
            }

            let snapshot = try await query.getDocuments()

            let allExercises = snapshot.documents.compactMap { document -> Exercise? in
                try? document.data(as: Exercise.self)
            }

            if !searchText.isEmpty {
                exercises = allExercises.filter { exercise in
                    exercise.title.lowercased().contains(searchText.lowercased())
                }
            } else {
                exercises = allExercises
            }

        } catch {
            errorMessage = "Error searching exercises: \(error.localizedDescription)"
            exercises = []
        }

        isLoading = false
    }
}
