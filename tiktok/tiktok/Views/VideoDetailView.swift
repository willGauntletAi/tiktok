import AVKit
import SwiftUI
import UIKit

struct VideoDetailView: View {
  let workoutPlan: WorkoutPlan
  let workoutIndex: Int?
  let exerciseIndex: Int?
  @State private var player: AVPlayer?
  @State private var isExpanded = false
  @State private var firstLineDescription: String = ""
  @State private var fullDescription: String = ""
  @Environment(\.dismiss) private var dismiss
  @Environment(\.presentationMode) var presentationMode

  private var currentWorkout: Workout? {
    guard let workoutIndex = workoutIndex else { return nil }
    return workoutPlan.workouts[workoutIndex].workout
  }

  private var currentWorkoutMetadata: WorkoutWithMetadata? {
    guard let workoutIndex = workoutIndex else { return nil }
    return workoutPlan.workouts[workoutIndex]
  }

  private var currentExercise: Exercise? {
    guard let workoutIndex = workoutIndex,
      let exerciseIndex = exerciseIndex
    else { return nil }
    return workoutPlan.workouts[workoutIndex].workout.exercises[exerciseIndex]
  }

  private var title: String {
    if let exercise = currentExercise {
      return exercise.title
    } else if let workout = currentWorkout {
      return workout.title
    } else {
      return workoutPlan.title
    }
  }

  private var description: String {
    if let exercise = currentExercise {
      return exercise.description
    } else if let workout = currentWorkout {
      return workout.description
    } else {
      return workoutPlan.description
    }
  }

  private var videoUrl: String {
    if let exercise = currentExercise {
      return exercise.videoUrl
    } else if let workout = currentWorkout {
      return workout.videoUrl
    } else {
      return workoutPlan.videoUrl
    }
  }

  private var difficulty: Difficulty {
    if let exercise = currentExercise {
      return exercise.difficulty
    } else if let workout = currentWorkout {
      return workout.difficulty
    } else {
      return workoutPlan.difficulty
    }
  }

  private var targetMuscles: [String] {
    if let exercise = currentExercise {
      return exercise.targetMuscles
    } else if let workout = currentWorkout {
      return workout.targetMuscles
    } else {
      return workoutPlan.targetMuscles
    }
  }

  private func navigateToNext() {
    // If we're viewing the workout plan video
    if workoutIndex == nil {
      if !workoutPlan.workouts.isEmpty {
        NavigationUtil.navigate(
          to: VideoDetailView(
            workoutPlan: workoutPlan,
            workoutIndex: 0,
            exerciseIndex: nil
          ))
      }
      return
    }

    // If we're viewing an exercise within a workout
    if let currentWorkoutIndex = workoutIndex, let currentExerciseIndex = exerciseIndex {
      let workout = workoutPlan.workouts[currentWorkoutIndex]
      // If there are more exercises in current workout
      if currentExerciseIndex + 1 < workout.workout.exercises.count {
        NavigationUtil.navigate(
          to: VideoDetailView(
            workoutPlan: workoutPlan,
            workoutIndex: currentWorkoutIndex,
            exerciseIndex: currentExerciseIndex + 1
          ))
      }
      // If we're at last exercise but there are more workouts
      else if currentWorkoutIndex + 1 < workoutPlan.workouts.count {
        NavigationUtil.navigate(
          to: VideoDetailView(
            workoutPlan: workoutPlan,
            workoutIndex: currentWorkoutIndex + 1,
            exerciseIndex: nil
          ))
      }
    }
    // If we're viewing a workout
    else if let currentWorkoutIndex = workoutIndex {
      let workout = workoutPlan.workouts[currentWorkoutIndex]
      // Navigate to first exercise if available
      if !workout.workout.exercises.isEmpty {
        NavigationUtil.navigate(
          to: VideoDetailView(
            workoutPlan: workoutPlan,
            workoutIndex: currentWorkoutIndex,
            exerciseIndex: 0
          ))
      }
      // Otherwise try to navigate to next workout
      else if currentWorkoutIndex + 1 < workoutPlan.workouts.count {
        NavigationUtil.navigate(
          to: VideoDetailView(
            workoutPlan: workoutPlan,
            workoutIndex: currentWorkoutIndex + 1,
            exerciseIndex: nil
          ))
      }
    }
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomLeading) {
        // Video Player
        if let videoUrl = URL(string: videoUrl) {
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
          Text(title)
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
                value: difficulty.rawValue.capitalized)

              DetailRow(
                title: "Target Muscles",
                value: targetMuscles.joined(separator: ", "))

              if let exercise = currentExercise {
                DetailRow(title: "Duration", value: "\(exercise.duration) seconds")
              } else if let workoutMeta = currentWorkoutMetadata {
                DetailRow(
                  title: "Total Duration",
                  value: "\(workoutMeta.workout.totalDuration) seconds")
                DetailRow(
                  title: "Exercises",
                  value: "\(workoutMeta.workout.exercises.count)")
                DetailRow(
                  title: "Schedule",
                  value: "Week \(workoutMeta.weekNumber), Day \(workoutMeta.dayOfWeek)")
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
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation(.easeInOut) {
            isExpanded.toggle()
          }
        }

        // Swipe indicator
        HStack {
          Spacer()
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.5))
            .frame(width: 4, height: 50)
            .padding(.trailing)
        }
        .frame(maxHeight: .infinity)
      }
      .simultaneousGesture(
        DragGesture()
          .onEnded { value in
            // Handle left edge swipe for back navigation
            if value.startLocation.x < 50 && value.translation.width > 100 {
              dismiss()
            }
            // Handle right to left swipe for next video
            else if value.translation.width < -50 {
              navigateToNext()
            }
          }
      )
    }
    .navigationBarBackButtonHidden(true)
    .toolbar(.hidden, for: .tabBar)
    .onAppear {
      // Set up description text
      fullDescription = description
      if let firstLine = description.components(separatedBy: .newlines).first {
        firstLineDescription = firstLine
      } else {
        firstLineDescription = description
      }
    }
  }
}

// Helper for programmatic navigation
private enum NavigationUtil {
  static func navigate<V: View>(to view: V) {
    let window = UIApplication.shared.windows.first { $0.isKeyWindow }
    if let rootViewController = window?.rootViewController,
      let navigationController = rootViewController.findNavigationController()
    {
      let hostingController = UIHostingController(rootView: view)
      navigationController.pushViewController(hostingController, animated: true)
    }
  }
}

extension UIViewController {
  func findNavigationController() -> UINavigationController? {
    if let nav = self as? UINavigationController {
      return nav
    }
    for child in children {
      if let nav = child.findNavigationController() {
        return nav
      }
    }
    return parent?.findNavigationController()
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
