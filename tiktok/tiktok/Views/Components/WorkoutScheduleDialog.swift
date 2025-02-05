import SwiftUI

struct WorkoutScheduleDialog: View {
  let workout: Workout
  let initialWeek: Int
  let initialDay: Int
  @Binding var isPresented: Bool
  let onSchedule: (Int, Int) -> Void

  @State private var weekNumber: Int
  @State private var selectedDay: Int

  init(
    workout: Workout,
    initialWeek: Int,
    initialDay: Int,
    isPresented: Binding<Bool>,
    onSchedule: @escaping (Int, Int) -> Void
  ) {
    self.workout = workout
    self.initialWeek = initialWeek
    self.initialDay = initialDay
    self._isPresented = isPresented
    self.onSchedule = onSchedule
    self._weekNumber = State(initialValue: initialWeek)
    self._selectedDay = State(initialValue: initialDay)
  }

  private let daysOfWeek = [
    (1, "Monday"),
    (2, "Tuesday"),
    (3, "Wednesday"),
    (4, "Thursday"),
    (5, "Friday"),
    (6, "Saturday"),
    (7, "Sunday"),
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("Edit Schedule")) {
          Text(workout.title)
            .font(.headline)

          Stepper(
            "Week \(weekNumber)",
            value: $weekNumber,
            in: 1...12
          )

          Picker("Day of Week", selection: $selectedDay) {
            ForEach(daysOfWeek, id: \.0) { day in
              Text(day.1).tag(day.0)
            }
          }
        }
      }
      .navigationTitle("Edit Schedule")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isPresented = false
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSchedule(weekNumber, selectedDay)
            isPresented = false
          }
        }
      }
    }
  }
}
