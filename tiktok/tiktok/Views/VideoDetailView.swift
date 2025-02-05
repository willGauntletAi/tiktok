import AVKit
import SwiftUI

struct VideoDetailView<T>: View {
  let item: T
  let type: String
  @State private var player: AVPlayer?
  @State private var isExpanded = false
  @State private var firstLineDescription: String = ""
  @State private var fullDescription: String = ""
  @State private var showExerciseCompletion = false
  @GestureState private var dragOffset: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomLeading) {
        // Video Player
        if let videoUrl = URL(
          string: (item as? Exercise)?.videoUrl ?? (item as? Workout)?.videoUrl ?? "")
        {
          VStack {
            Spacer()
            VideoPlayer(player: player ?? AVPlayer())
              .frame(width: geometry.size.width, height: geometry.size.height)
              .aspectRatio(contentMode: .fit)
              .onAppear {
                // Initialize player and start playback
                player = AVPlayer(url: videoUrl)
                player?.play()
              }
              .onDisappear {
                // Stop and clean up player when view disappears
                player?.pause()
                player = nil
              }
            Spacer()
          }
          .edgesIgnoringSafeArea(.all)
        }

        // Overlay content
        VStack(alignment: .leading, spacing: 8) {
          // Title
          Text((item as? Exercise)?.title ?? (item as? Workout)?.title ?? "")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .shadow(radius: 2)

          // Description
          Text(isExpanded ? fullDescription : firstLineDescription)
            .font(.body)
            .foregroundColor(.white)
            .shadow(radius: 2)
            .lineLimit(isExpanded ? nil : 1)

          if isExpanded {
            // Additional details
            VStack(alignment: .leading, spacing: 12) {
              DetailRow(
                title: "Difficulty",
                value: ((item as? Exercise)?.difficulty.rawValue
                  ?? (item as? Workout)?.difficulty.rawValue)
                  ?? "beginner"
                  .capitalized)

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
          }
        }
        .padding()
        .background(
          LinearGradient(
            gradient: Gradient(colors: [.black.opacity(0.7), .clear]),
            startPoint: .bottom,
            endPoint: .top
          )
        )
        .frame(maxWidth: isExpanded ? .infinity : geometry.size.width * 0.8)
        .onTapGesture {
          withAnimation(.easeInOut) {
            isExpanded.toggle()
          }
        }

        // Swipe indicator for exercises
        if item is Exercise {
          HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.white.opacity(0.5))
              .frame(width: 4, height: 50)
              .padding(.trailing)
          }
          .frame(maxHeight: .infinity)
        }
      }
      .offset(x: dragOffset)
      .gesture(
        DragGesture()
          .updating($dragOffset) { value, state, _ in
            if item is Exercise {
              state = max(-50, min(0, value.translation.width))
            }
          }
          .onEnded { value in
            if item is Exercise && value.translation.width < -50 {
              showExerciseCompletion = true
            }
          }
      )
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      // Set up description text
      let description = (item as? Exercise)?.description ?? (item as? Workout)?.description ?? ""
      fullDescription = description
      if let firstLine = description.components(separatedBy: .newlines).first {
        firstLineDescription = firstLine
      } else {
        firstLineDescription = description
      }
    }
    .background(
      NavigationLink(value: showExerciseCompletion) {
        EmptyView()
      }
    )
    .navigationDestination(isPresented: $showExerciseCompletion) {
      if let exercise = item as? Exercise {
        ExerciseCompletionView(exercise: exercise)
      }
    }
  }
}

struct DetailRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.7))
        .shadow(radius: 2)

      Text(value)
        .font(.body)
        .foregroundColor(.white)
        .shadow(radius: 2)
    }
  }
}
