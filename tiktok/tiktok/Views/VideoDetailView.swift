import AVKit
import SwiftUI
import UIKit

struct VideoDetailView<T>: View {
  let item: T
  let type: String
  @State private var player: AVPlayer?
  @State private var isExpanded = false
  @State private var firstLineDescription: String = ""
  @State private var fullDescription: String = ""
  @State private var showExerciseCompletion = false
  @State private var showWorkoutCompletion = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.presentationMode) var presentationMode

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
          Spacer()

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

        // Swipe indicator for exercises or workouts
        if item is Exercise || item is Workout {
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
      .gesture(
        DragGesture()
          .onEnded { value in
            // Handle left edge swipe for back navigation
            if value.startLocation.x < 50 && value.translation.width > 100 {
              presentationMode.wrappedValue.dismiss()
            }
            // Handle right edge swipe for exercise/workout completion
            else if value.translation.width < -50 {
              if item is Exercise {
                showExerciseCompletion = true
              } else if item is Workout {
                showWorkoutCompletion = true
              }
            }
          }
      )
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .tabBar)
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
      Group {
        NavigationLink(isActive: $showExerciseCompletion) {
          if let exercise = item as? Exercise {
            ExerciseCompletionView(exercise: exercise)
          }
        } label: {
          EmptyView()
        }
        
        NavigationLink(isActive: $showWorkoutCompletion) {
          if let workout = item as? Workout {
            WorkoutCompletionView(workout: workout)
          }
        } label: {
          EmptyView()
        }
      }
    )
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
