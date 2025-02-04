import SwiftUI

struct FindExerciseView: View {
  @StateObject private var viewModel = FindExerciseViewModel()
  @FocusState private var focusedField: Field?
  var onExerciseSelected: ((Exercise) -> Void)?

  enum Field {
    case instructorEmail
    case title
  }

  var body: some View {
    VStack(spacing: 0) {
      // Search Fields
      VStack(spacing: 16) {
        TextField("Instructor Email", text: $viewModel.instructorEmail)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
          .focused($focusedField, equals: .instructorEmail)
          .submitLabel(.next)

        TextField("Exercise Title", text: $viewModel.searchText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .focused($focusedField, equals: .title)
          .submitLabel(.search)
      }
      .padding()
      .background(Color(.systemBackground))
      .onSubmit {
        switch focusedField {
        case .instructorEmail:
          focusedField = .title
        case .title:
          focusedField = nil
          Task {
            await viewModel.searchExercises()
          }
        case .none:
          break
        }
      }

      // Results
      ScrollView {
        if viewModel.isLoading {
          ProgressView()
            .padding()
        } else if let error = viewModel.errorMessage {
          Text(error)
            .foregroundColor(.red)
            .padding()
        } else if viewModel.exercises.isEmpty {
          Text("No exercises found")
            .foregroundColor(.gray)
            .padding()
        } else {
          LazyVStack(spacing: 16) {
            ForEach(viewModel.exercises) { exercise in
              if let onSelect = onExerciseSelected {
                ExerciseCard(exercise: exercise)
                  .padding(.horizontal)
                  .onTapGesture {
                    onSelect(exercise)
                  }
              } else {
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                  ExerciseCard(exercise: exercise)
                    .padding(.horizontal)
                }
              }
            }
          }
          .padding(.vertical)
        }
      }
    }
    .navigationTitle("Find Exercise")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: viewModel.instructorEmail) { _ in
      Task {
        await viewModel.searchExercises()
      }
    }
    .onChange(of: viewModel.searchText) { _ in
      Task {
        await viewModel.searchExercises()
      }
    }
    .onTapGesture {
      focusedField = nil
    }
  }
}
