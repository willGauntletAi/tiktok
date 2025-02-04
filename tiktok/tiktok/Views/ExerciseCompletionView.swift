import SwiftUI

struct ExerciseCompletionView: View {
  let exercise: Exercise
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    ScrollView {
      ExerciseCompletionComponent(
        exercise: exercise,
        onComplete: {
          presentationMode.wrappedValue.dismiss()
        }
      )
      .padding(.vertical)
    }
    .navigationTitle("Record Exercise")
    .navigationBarTitleDisplayMode(.inline)
  }
}
