import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct ExerciseInstance: Identifiable {
  let id: String
  let exercise: Exercise

  init(exercise: Exercise) {
    self.id = UUID().uuidString
    self.exercise = exercise
  }
}

@MainActor
class CreateWorkoutViewModel: ObservableObject {
  @Published var workout: Workout
  @Published var selectedExercises: [ExerciseInstance] = []
  @Published var isLoading = false
  @Published var errorMessage: String?
  @Published var showExerciseSelector = false
  @Published var videoThumbnail: UIImage?
  @Published var videoData: Data?
  @Published var showCamera = false
  var navigator: Navigator?

  private let db = Firestore.firestore()

  init() {
    self.workout = Workout.empty()
  }

  var canSave: Bool {
    !workout.title.isEmpty && !workout.description.isEmpty && !selectedExercises.isEmpty
      && videoData != nil  // Require video to be selected
  }

  func addExercise(_ exercise: Exercise) {
    selectedExercises.append(ExerciseInstance(exercise: exercise))
    updateTotalDuration()
  }

  func removeExercise(_ exercise: Exercise) {
    selectedExercises.removeAll { $0.exercise.id == exercise.id }
    updateTotalDuration()
  }

  func removeExercise(at offsets: IndexSet) {
    selectedExercises.remove(atOffsets: offsets)
    updateTotalDuration()
  }

  func moveExercise(from source: IndexSet, to destination: Int) {
    selectedExercises.move(fromOffsets: source, toOffset: destination)
  }

  private func updateTotalDuration() {
    workout.totalDuration = selectedExercises.reduce(0) { $0 + $1.exercise.duration }
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

  func saveWorkout() async {
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

        // 3. Create workout document
        workout.type = "workout"
        workout.instructorId = userId
        workout.exercises = selectedExercises.map { $0.exercise }
        workout.videoUrl = videoUrl
        workout.thumbnailUrl = thumbnailUrl
        workout.createdAt = Date()
        workout.updatedAt = Date()

        let workoutRef = db.collection("videos").document()
        workout.id = workoutRef.documentID

        try await workoutRef.setData(workout.dictionary)

        // 4. Reset form
        self.workout = Workout.empty()
        self.selectedExercises = []
        self.videoData = nil
        self.videoThumbnail = nil

        // 5. Trigger navigation to profile
        navigator?.navigate(to: .profile)
      }
    } catch {
      errorMessage = "Failed to save workout: \(error.localizedDescription)"
    }

    isLoading = false
  }
}
