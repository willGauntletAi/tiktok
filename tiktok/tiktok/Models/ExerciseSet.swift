import Foundation

struct ExerciseSet: Identifiable {
  let id = UUID()
  var reps: Int
  var weight: Double?
  var notes: String
}
