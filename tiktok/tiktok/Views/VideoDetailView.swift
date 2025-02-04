import AVKit
import SwiftUI

struct VideoDetailView<T>: View {
  let item: T
  let type: String
  @State private var player: AVPlayer?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Video Player
        if let videoUrl = URL(
          string: (item as? Exercise)?.videoUrl ?? (item as? Workout)?.videoUrl ?? "")
        {
          VideoPlayer(player: AVPlayer(url: videoUrl))
            .frame(height: 250)
        }

        // Title and Description
        VStack(alignment: .leading, spacing: 8) {
          Text((item as? Exercise)?.title ?? (item as? Workout)?.title ?? "")
            .font(.title2)
            .fontWeight(.bold)

          Text((item as? Exercise)?.description ?? (item as? Workout)?.description ?? "")
            .font(.body)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)

        // Details
        VStack(alignment: .leading, spacing: 12) {
          DetailRow(
            title: "Difficulty",
            value: ((item as? Exercise)?.difficulty ?? (item as? Workout)?.difficulty)?.rawValue
              .capitalized ?? "")

          DetailRow(
            title: "Target Muscles",
            value: ((item as? Exercise)?.targetMuscles ?? (item as? Workout)?.targetMuscles)?
              .joined(separator: ", ") ?? "")

          if let exercise = item as? Exercise {
            DetailRow(title: "Duration", value: "\(exercise.duration) seconds")
          } else if let workout = item as? Workout {
            DetailRow(title: "Total Duration", value: "\(workout.totalDuration) seconds")
            DetailRow(title: "Exercises", value: "\(workout.exercises.count)")
          }
        }
        .padding(.horizontal)
      }
      .padding(.vertical)
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct DetailRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline)
        .foregroundColor(.secondary)

      Text(value)
        .font(.body)
    }
  }
}
