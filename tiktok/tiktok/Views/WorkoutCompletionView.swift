import SwiftUI

struct WorkoutCompletionView: View {
  let workout: Workout
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    ScrollView {
      WorkoutCompletionComponent(
        workout: workout,
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
