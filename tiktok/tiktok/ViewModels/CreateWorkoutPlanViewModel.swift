@preconcurrency import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct WorkoutInstance: Identifiable {
    let id: String
    let workoutWithMeta: WorkoutWithMetadata

    init(workout: Workout, weekNumber: Int, dayOfWeek: Int) {
        id = UUID().uuidString
        workoutWithMeta = WorkoutWithMetadata(
            workout: workout,
            weekNumber: weekNumber,
            dayOfWeek: dayOfWeek
        )
    }
}

@MainActor
class CreateWorkoutPlanViewModel: ObservableObject {
    @Published var workoutPlan: WorkoutPlan
    @Published var selectedWorkouts: [WorkoutInstance] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var showWorkoutSelector = false
    @Published var videoThumbnail: UIImage?
    @Published var videoData: Data?
    @Published var showCamera = false
    @Published var editingWorkoutId: String?
    @Published var showScheduleEditor = false

    var navigator: Navigator?
    var dismiss: (() -> Void)?

    private let db = Firestore.firestore()

    init() {
        workoutPlan = WorkoutPlan.empty()
    }

    var canSave: Bool {
        !workoutPlan.title.isEmpty && !workoutPlan.description.isEmpty && !selectedWorkouts.isEmpty
            && videoData != nil && workoutPlan.duration > 0
    }

    func addWorkout(_ workout: Workout) {
        // Always add to week 1, day 1 initially
        selectedWorkouts.append(
            WorkoutInstance(workout: workout, weekNumber: 1, dayOfWeek: 1)
        )
        sortWorkouts()
        workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
    }

    func updateWorkoutSchedule(workoutId: String, weekNumber: Int, dayOfWeek: Int) {
        if let index = selectedWorkouts.firstIndex(where: { $0.id == workoutId }) {
            selectedWorkouts[index] = WorkoutInstance(
                workout: selectedWorkouts[index].workoutWithMeta.workout,
                weekNumber: weekNumber,
                dayOfWeek: dayOfWeek
            )
            sortWorkouts()
            workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
        }
    }

    func editWorkoutSchedule(_ workoutId: String) {
        editingWorkoutId = workoutId
        showScheduleEditor = true
    }

    func removeWorkout(_ workout: Workout) {
        selectedWorkouts.removeAll { $0.workoutWithMeta.workout.id == workout.id }
        workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
    }

    func removeWorkout(at offsets: IndexSet) {
        selectedWorkouts.remove(atOffsets: offsets)
        workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
    }

    func moveWorkout(from source: IndexSet, to destination: Int) {
        selectedWorkouts.move(fromOffsets: source, toOffset: destination)
        workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
    }

    private func sortWorkouts() {
        selectedWorkouts.sort { first, second in
            let firstWeek = first.workoutWithMeta.weekNumber
            let secondWeek = second.workoutWithMeta.weekNumber

            if firstWeek != secondWeek {
                return firstWeek < secondWeek
            }

            return first.workoutWithMeta.dayOfWeek < second.workoutWithMeta.dayOfWeek
        }
    }

    func processVideoData(_ data: Data) async {
        videoData = nil
        isUploading = true

        do {
            videoData = data

            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString + ".mov")
            try data.write(to: tmpURL)

            let asset = AVURLAsset(url: tmpURL)

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)

            // Use new async API for generating thumbnails
            let image = try await imageGenerator.image(at: .zero)
            videoThumbnail = UIImage(cgImage: image.image)

            try FileManager.default.removeItem(at: tmpURL)

        } catch {
            errorMessage = "Failed to process video: \(error.localizedDescription)"
            videoData = nil
            videoThumbnail = nil
        }

        isUploading = false
    }

    func saveWorkoutPlan() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "User not authenticated"
            return
        }

        guard let uploadData = videoData else {
            errorMessage = "No video selected"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Upload video to Firebase Storage
            let videoFileName = "\(UUID().uuidString).mp4"
            let videoRef = Storage.storage().reference().child("videos/\(videoFileName)")
            _ = try await videoRef.putDataAsync(uploadData)
            let videoUrl = try await videoRef.downloadURL().absoluteString

            // 2. Upload thumbnail
            if let thumbnailData = videoThumbnail?.jpegData(compressionQuality: 0.7) {
                let thumbnailFileName = "\(UUID().uuidString).jpg"
                let thumbnailRef = Storage.storage().reference().child("thumbnails/\(thumbnailFileName)")
                _ = try await thumbnailRef.putDataAsync(thumbnailData)
                let thumbnailUrl = try await thumbnailRef.downloadURL().absoluteString

                // 3. Create workout plan document
                workoutPlan.type = "workoutPlan"
                workoutPlan.instructorId = userId
                workoutPlan.videoUrl = videoUrl
                workoutPlan.thumbnailUrl = thumbnailUrl
                workoutPlan.createdAt = Date()
                workoutPlan.updatedAt = Date()
                workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }

                let workoutPlanRef = db.collection("videos").document()
                workoutPlan.id = workoutPlanRef.documentID

                try await workoutPlanRef.setData(workoutPlan.dictionary)

                // 4. Reset form
                workoutPlan = WorkoutPlan.empty()
                selectedWorkouts = []
                videoData = nil
                videoThumbnail = nil

                // 5. Dismiss the creation view
                dismiss?()
            }
        } catch {
            errorMessage = "Failed to save workout plan: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
