import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import AVFoundation

@MainActor
class CreateExerciseViewModel: ObservableObject {
    @Published var exercise = Exercise.empty()
    @Published var videoThumbnail: UIImage?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isUploading = false
    
    private var videoData: Data?
    
    var canUpload: Bool {
        !exercise.title.isEmpty &&
        !exercise.description.isEmpty &&
        videoData != nil &&
        !exercise.targetMuscles.isEmpty &&
        exercise.duration > 0
    }
    
    func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            let movieData = try await item.loadTransferable(type: Data.self)
            self.videoData = movieData
            
            // Generate thumbnail
            if let movieData = movieData {
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try movieData.write(to: tmpURL)
                
                let asset = AVAsset(url: tmpURL)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                self.videoThumbnail = UIImage(cgImage: cgImage)
                
                // Get video duration
                let duration = try await asset.load(.duration)
                self.exercise.duration = Int(duration.seconds)
                
                try FileManager.default.removeItem(at: tmpURL)
            }
        } catch {
            showError = true
            errorMessage = "Failed to load video: \(error.localizedDescription)"
        }
    }
    
    func uploadExercise() async {
        guard let videoData = videoData else { return }
        isUploading = true
        
        do {
            // 1. Upload video to Firebase Storage
            let videoFileName = "\(UUID().uuidString).mp4"
            let videoRef = Storage.storage().reference().child("videos/\(videoFileName)")
            _ = try await videoRef.putDataAsync(videoData)
            let videoUrl = try await videoRef.downloadURL().absoluteString
            
            // 2. Upload thumbnail
            if let thumbnailData = videoThumbnail?.jpegData(compressionQuality: 0.7) {
                let thumbnailFileName = "\(UUID().uuidString).jpg"
                let thumbnailRef = Storage.storage().reference().child("thumbnails/\(thumbnailFileName)")
                _ = try await thumbnailRef.putDataAsync(thumbnailData)
                let thumbnailUrl = try await thumbnailRef.downloadURL().absoluteString
                
                // 3. Update exercise with URLs
                exercise.videoUrl = videoUrl
                exercise.thumbnailUrl = thumbnailUrl
                
                // 4. Save to Firestore
                let db = Firestore.firestore()
                try await db.collection("videos").document(exercise.id).setData(exercise.dictionary)
                
                // 5. Reset form
                exercise = Exercise.empty()
                videoData = nil
                videoThumbnail = nil
            }
        } catch {
            showError = true
            errorMessage = "Failed to upload exercise: \(error.localizedDescription)"
        }
        
        isUploading = false
    }
}

// Helper extension to convert Exercise to dictionary
extension Exercise {
    var dictionary: [String: Any] {
        [
            "id": id,
            "type": type,
            "title": title,
            "description": description,
            "instructorId": instructorId,
            "videoUrl": videoUrl,
            "thumbnailUrl": thumbnailUrl,
            "difficulty": difficulty.rawValue,
            "targetMuscles": targetMuscles,
            "duration": duration,
            "sets": sets as Any,
            "reps": reps as Any,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
    }
} 