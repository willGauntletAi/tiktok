import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct WorkoutInstance: Identifiable {
  let id: String
  let workoutWithMeta: WorkoutWithMetadata

  init(workout: Workout, weekNumber: Int, dayOfWeek: Int) {
    self.id = UUID().uuidString
    self.workoutWithMeta = WorkoutWithMetadata(
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
  @Published var errorMessage: String?
  @Published var showWorkoutSelector = false
  @Published var videoThumbnail: UIImage?
  @Published var videoData: Data?
  @Published var showCamera = false
  @Published var shouldNavigateToProfile = false

  private let db = Firestore.firestore()
  private let navigationVM = NavigationViewModel.shared

  init() {
    self.workoutPlan = WorkoutPlan.empty()
  }

  var canSave: Bool {
    !workoutPlan.title.isEmpty && !workoutPlan.description.isEmpty && !selectedWorkouts.isEmpty
      && videoData != nil && workoutPlan.duration > 0
  }

  func addWorkout(_ workout: Workout) {
    // Calculate week number and day of week based on the workout's position
    let position = selectedWorkouts.count
    let weekNumber = (position / 7) + 1
    let dayOfWeek = (position % 7) + 1

    selectedWorkouts.append(
      WorkoutInstance(workout: workout, weekNumber: weekNumber, dayOfWeek: dayOfWeek))
    updateWorkoutMetadata()
  }

  func removeWorkout(_ workout: Workout) {
    selectedWorkouts.removeAll { $0.workoutWithMeta.workout.id == workout.id }
    updateWorkoutMetadata()
  }

  func removeWorkout(at offsets: IndexSet) {
    selectedWorkouts.remove(atOffsets: offsets)
    updateWorkoutMetadata()
  }

  func moveWorkout(from source: IndexSet, to destination: Int) {
    selectedWorkouts.move(fromOffsets: source, toOffset: destination)
    updateWorkoutMetadata()
  }

  private func updateWorkoutMetadata() {
    // Recalculate week numbers and days for all workouts
    for (index, workoutInstance) in selectedWorkouts.enumerated() {
      let weekNumber = (index / 7) + 1
      let dayOfWeek = (index % 7) + 1
      selectedWorkouts[index] = WorkoutInstance(
        workout: workoutInstance.workoutWithMeta.workout,
        weekNumber: weekNumber,
        dayOfWeek: dayOfWeek
      )
    }
    workoutPlan.workouts = selectedWorkouts.map { $0.workoutWithMeta }
  }

  func loadVideo(from item: PhotosPickerItem?) async {
    guard let item = item else { return }

    videoData = nil

    do {
      let dataLoadTask = Task { try await item.loadTransferable(type: Data.self) }

      guard let data = try await dataLoadTask.value else {
        throw NSError(
          domain: "", code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Could not load video data"])
      }

      self.videoData = data

      let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".mov")
      try data.write(to: tmpURL)

      let asset = AVAsset(url: tmpURL)

      let imageGenerator = AVAssetImageGenerator(asset: asset)
      imageGenerator.appliesPreferredTrackTransform = true
      imageGenerator.maximumSize = CGSize(width: 400, height: 400)
      imageGenerator.requestedTimeToleranceBefore = .zero
      imageGenerator.requestedTimeToleranceAfter = .zero

      let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
      self.videoThumbnail = UIImage(cgImage: cgImage)

      try FileManager.default.removeItem(at: tmpURL)

    } catch {
      errorMessage = "Failed to load video: \(error.localizedDescription)"
      videoData = nil
      videoThumbnail = nil
    }
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
        self.workoutPlan = WorkoutPlan.empty()
        self.selectedWorkouts = []
        self.videoData = nil
        self.videoThumbnail = nil

        // 5. Trigger navigation to profile
        self.shouldNavigateToProfile = true
        self.navigationVM.navigateToProfile()
      }
    } catch {
      errorMessage = "Failed to save workout plan: \(error.localizedDescription)"
    }

    isLoading = false
  }
}
