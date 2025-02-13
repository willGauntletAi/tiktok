import FirebaseAuth
import FirebaseFirestore
import Foundation

struct ExerciseState {
    var sets: [ExerciseSet]
    var isLoading: Bool
    var showError: Bool
    var errorMessage: String
}

struct WorkoutCompletionData: Sendable {
    let workoutId: String
    let userId: String
    let exerciseCompletions: [String]
    let startedAt: Date
    let notes: String

    var asDictionary: [String: Any] {
        [
            "workoutId": workoutId,
            "userId": userId,
            "exerciseCompletions": exerciseCompletions,
            "startedAt": Timestamp(date: startedAt),
            "notes": notes,
        ]
    }
}

struct WorkoutCompletionUpdateData: Sendable {
    let finishedAt: Date

    var asDictionary: [String: Any] {
        [
            "finishedAt": Timestamp(date: finishedAt),
        ]
    }
}

class WorkoutCompletionViewModel: ObservableObject {
    let workoutId: String
    let workout: Workout
    @Published var isLoadingHistory = false
    @Published var recentCompletions: [WorkoutCompletion] = []
    @Published var hasMoreHistory = false

    // Active workout state
    @Published var isStarted = false
    @Published var startTime: Date?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var workoutCompletionId: String?
    @Published var exerciseStates: [String: ExerciseState] = [:]

    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    private let db = Firestore.firestore()

    init(workoutId: String, workout: Workout) {
        self.workoutId = workoutId
        self.workout = workout
    }

    @MainActor
    func startWorkout() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }

        let now = Date()
        let completionData = WorkoutCompletionData(
            workoutId: workoutId,
            userId: userId,
            exerciseCompletions: [],
            startedAt: now,
            notes: ""
        )

        let docRef = try await db.collection("workoutCompletions").addDocument(data: completionData.asDictionary)
        workoutCompletionId = docRef.documentID
        startTime = now
        isStarted = true

        // Initialize exercise states
        for exercise in workout.exercises {
            exerciseStates[exercise.id] = ExerciseState(
                sets: [ExerciseSet(reps: 0)],
                isLoading: false,
                showError: false,
                errorMessage: ""
            )
        }
    }

    @MainActor
    func cancelWorkout() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let workoutCompletionId = workoutCompletionId else { return }

        try await db.collection("workoutCompletions").document(workoutCompletionId).delete()
        isStarted = false
        self.workoutCompletionId = nil
        startTime = nil
        exerciseStates = [:]
    }

    @MainActor
    func checkWorkoutCompletion() async throws {
        guard let workoutCompletionId = workoutCompletionId else { return }

        let allExercises = Set(workout.exercises.map { $0.id })
        let completedExercises = Set(exerciseStates.filter { $0.value.sets.allSatisfy { $0.reps > 0 } }.keys)

        if completedExercises == allExercises {
            let updateData = WorkoutCompletionUpdateData(finishedAt: Date())
            try await db.collection("workoutCompletions").document(workoutCompletionId).updateData(updateData.asDictionary)
        }
    }

    @MainActor
    func fetchRecentCompletions() async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let query = db.collection("workoutCompletions")
                .whereField("workoutId", isEqualTo: workoutId)
                .order(by: "startedAt", descending: true)
                .limit(to: pageSize)

            let snapshot = try await query.getDocuments()
            lastDocument = snapshot.documents.last

            recentCompletions = snapshot.documents.compactMap { document in
                WorkoutCompletion(document: document)
            }

            hasMoreHistory = !snapshot.documents.isEmpty && snapshot.documents.count == pageSize
        } catch {
            print("Error fetching workout completions: \(error)")
        }
    }

    @MainActor
    func fetchMoreHistory() async {
        guard !isLoadingHistory, let lastDocument = lastDocument else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let query = db.collection("workoutCompletions")
                .whereField("workoutId", isEqualTo: workoutId)
                .order(by: "startedAt", descending: true)
                .start(afterDocument: lastDocument)
                .limit(to: pageSize)

            let snapshot = try await query.getDocuments()
            self.lastDocument = snapshot.documents.last

            let newCompletions = snapshot.documents.compactMap { document in
                WorkoutCompletion(document: document)
            }

            recentCompletions.append(contentsOf: newCompletions)
            hasMoreHistory = !snapshot.documents.isEmpty && snapshot.documents.count == pageSize
        } catch {
            print("Error fetching more workout completions: \(error)")
        }
    }
}
