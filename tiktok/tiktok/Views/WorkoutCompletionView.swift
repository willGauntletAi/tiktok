import SwiftUI

struct WorkoutCompletionView: View {
  let workout: Workout
  @StateObject private var viewModel: WorkoutCompletionViewModel
  @Environment(\.presentationMode) var presentationMode

  init(workout: Workout) {
    self.workout = workout
    self._viewModel = StateObject(
      wrappedValue: WorkoutCompletionViewModel(workoutId: workout.id, workout: workout))
  }

  var body: some View {
    ScrollView {
      WorkoutCompletionComponent(
        workout: workout,
        viewModel: viewModel,
        onComplete: {
          presentationMode.wrappedValue.dismiss()
        }
      )
      .padding(.vertical)
    }
    .navigationTitle("Complete Workout")
    .navigationBarTitleDisplayMode(.inline)
  }
}
