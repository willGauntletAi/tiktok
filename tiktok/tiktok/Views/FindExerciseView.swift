// import SwiftUI

// struct FindExerciseView: View {
//   @StateObject private var viewModel = FindExerciseViewModel()
//   @FocusState private var focusedField: Field?
//   var onExerciseSelected: ((Exercise) -> Void)?
//   var selectedExerciseIds: Set<String>

//   init(onExerciseSelected: ((Exercise) -> Void)? = nil, selectedExerciseIds: Set<String> = []) {
//     self.onExerciseSelected = onExerciseSelected
//     self.selectedExerciseIds = selectedExerciseIds
//   }

//   enum Field {
//     case instructorEmail
//     case title
//   }

//   var body: some View {
//     VStack(spacing: 0) {
//       // Search Fields
//       VStack(spacing: 16) {
//         VStack(alignment: .leading, spacing: 0) {
//           TextField("Instructor Email", text: $viewModel.instructorEmail)
//             .textFieldStyle(RoundedBorderTextFieldStyle())
//             .textInputAutocapitalization(.never)
//             .keyboardType(.emailAddress)
//             .focused($focusedField, equals: .instructorEmail)
//             .submitLabel(.next)
//             .onChange(of: viewModel.instructorEmail) { _ in
//               Task {
//                 await viewModel.searchEmails()
//               }
//             }
//             .onChange(of: focusedField) { field in
//               viewModel.isEmailFocused = (field == .instructorEmail)
//               if field == .instructorEmail {
//                 // Trigger search when field becomes focused
//                 Task {
//                   await viewModel.searchEmails()
//                 }
//               } else {
//                 viewModel.emailSuggestions = []
//               }
//             }

//           // Email Suggestions
//           if viewModel.isEmailFocused
//             && (!viewModel.instructorEmail.isEmpty || !viewModel.emailSuggestions.isEmpty)
//           {
//             ScrollView {
//               VStack(alignment: .leading, spacing: 0) {
//                 ForEach(viewModel.emailSuggestions, id: \.self) { email in
//                   Button(action: { viewModel.selectEmail(email) }) {
//                     Text(email)
//                       .padding(.vertical, 8)
//                       .padding(.horizontal, 12)
//                       .frame(maxWidth: .infinity, alignment: .leading)
//                   }
//                   .buttonStyle(.plain)

//                   if email != viewModel.emailSuggestions.last {
//                     Divider()
//                   }
//                 }
//               }
//             }
//             .frame(maxHeight: 200)
//             .background(Color(.systemBackground))
//             .cornerRadius(8)
//             .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
//           }
//         }

//         TextField("Exercise Title", text: $viewModel.searchText)
//           .textFieldStyle(RoundedBorderTextFieldStyle())
//           .focused($focusedField, equals: .title)
//           .submitLabel(.search)
//       }
//       .padding()
//       .background(Color(.systemBackground))
//       .onSubmit {
//         switch focusedField {
//         case .instructorEmail:
//           focusedField = .title
//         case .title:
//           focusedField = nil
//           Task {
//             await viewModel.searchExercises()
//           }
//         case .none:
//           break
//         }
//       }

//       // Results
//       ScrollView {
//         if viewModel.isLoading {
//           ProgressView()
//             .padding()
//         } else if let error = viewModel.errorMessage {
//           Text(error)
//             .foregroundColor(.red)
//             .padding()
//         } else if viewModel.exercises.isEmpty {
//           Text("No exercises found")
//             .foregroundColor(.gray)
//             .padding()
//         } else {
//           LazyVStack(spacing: 16) {
//             ForEach(viewModel.exercises) { exercise in
//               if let onSelect = onExerciseSelected {
//                 // Workout creation mode
//                 ExerciseResultCard(
//                   exercise: exercise,
//                   isSelected: selectedExerciseIds.contains(exercise.id),
//                   onToggle: onSelect
//                 )
//                 .padding(.horizontal)
//               } else {
//                 // Regular view mode
//                 NavigationLink(destination: VideoDetailView(item: exercise, type: "exercise")) {
//                   ExerciseCard(exercise: exercise)
//                     .padding(.horizontal)
//                 }
//               }
//             }
//           }
//           .padding(.vertical)
//         }
//       }
//     }
//     .background(
//       Color(.systemBackground)
//         .onTapGesture {
//           focusedField = nil
//         }
//     )
//     .navigationTitle("Find Exercise")
//     .navigationBarTitleDisplayMode(.inline)
//     .onChange(of: viewModel.searchText) { _ in
//       Task {
//         await viewModel.searchExercises()
//       }
//     }
//     .onAppear {
//       viewModel.selectedExerciseIds = selectedExerciseIds
//     }
//   }
// }

// struct ExerciseResultCard: View {
//   let exercise: Exercise
//   let isSelected: Bool
//   let onToggle: (Exercise) -> Void

//   var body: some View {
//     VStack(alignment: .leading, spacing: 12) {
//       ExerciseCard(exercise: exercise)

//       Button(action: { onToggle(exercise) }) {
//         HStack {
//           Image(systemName: isSelected ? "minus.circle.fill" : "plus.circle.fill")
//           Text(isSelected ? "Remove from Workout" : "Add to Workout")
//         }
//         .frame(maxWidth: .infinity)
//         .padding(.vertical, 8)
//         .background(isSelected ? Color.red : Color.blue)
//         .foregroundColor(.white)
//         .cornerRadius(8)
//       }
//     }
//     .padding(12)
//     .background(Color(.systemBackground))
//     .cornerRadius(12)
//     .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//   }
// }
