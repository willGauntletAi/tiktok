import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct CreateExerciseView: View {
  @StateObject private var viewModel = CreateExerciseViewModel()
  @State private var showingMuscleSelector = false
  @FocusState private var focusedField: Field?
  @Environment(\.presentationMode) var presentationMode

  enum Field {
    case title
    case description
    case duration
    case sets
    case reps
  }

  let muscleGroups = [
    "Chest", "Back", "Shoulders", "Biceps", "Triceps",
    "Legs", "Core", "Full Body",
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        VideoSelectionView(
          videoThumbnail: $viewModel.videoThumbnail,
          showCamera: $viewModel.showCamera,
          onVideoSelected: { item in
            await viewModel.loadVideo(from: item)
          }
        )

        GroupBox(label: Text("Details").bold()) {
          VStack(spacing: 12) {
            TextField("Title", text: $viewModel.exercise.title)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .focused($focusedField, equals: .title)

            TextField("Description", text: $viewModel.exercise.description, axis: .vertical)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .lineLimit(3...6)
              .focused($focusedField, equals: .description)

            Picker("Difficulty", selection: $viewModel.exercise.difficulty) {
              ForEach(Difficulty.allCases, id: \.self) { difficulty in
                Text(difficulty.rawValue.capitalized)
              }
            }
          }
        }
        .padding(.horizontal)

        GroupBox(label: Text("Target Muscles").bold()) {
          Button(action: { showingMuscleSelector = true }) {
            HStack {
              Text("Select Muscles")
              Spacer()
              Text("\(viewModel.exercise.targetMuscles.count) selected")
                .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
          }
        }
        .padding(.horizontal)

        GroupBox(label: Text("Exercise Specifics").bold()) {
          VStack(spacing: 12) {
            HStack {
              Text("Duration")
              Spacer()
              TextField("Seconds", value: $viewModel.exercise.duration, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .duration)
            }

            HStack {
              Text("Sets")
              Spacer()
              TextField("Optional", value: $viewModel.exercise.sets, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .sets)
            }

            HStack {
              Text("Reps")
              Spacer()
              TextField("Optional", value: $viewModel.exercise.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .reps)
            }
          }
        }
        .padding(.horizontal)

        Button(action: { Task { await viewModel.uploadExercise() } }) {
          if viewModel.isUploading {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .white))
          } else {
            Text("Upload Exercise")
          }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(viewModel.canUpload ? Color.blue : Color.gray)
        .foregroundColor(.white)
        .cornerRadius(10)
        .disabled(!viewModel.canUpload || viewModel.isUploading)
        .padding(.horizontal)
      }
      .padding(.vertical)
    }
    .navigationTitle("Create Exercise")
    .sheet(isPresented: $showingMuscleSelector) {
      VStack(spacing: 0) {
        HStack {
          Text("Select Muscles")
            .font(.headline)
          Spacer()
          Button("Done") {
            focusedField = nil
            showingMuscleSelector = false
          }
        }
        .padding()
        .background(Color(UIColor.systemBackground))

        List(muscleGroups, id: \.self) { muscle in
          let isSelected = viewModel.exercise.targetMuscles.contains(muscle)
          Button(action: {
            if isSelected {
              viewModel.exercise.targetMuscles.removeAll { $0 == muscle }
            } else {
              viewModel.exercise.targetMuscles.append(muscle)
            }
          }) {
            HStack {
              Text(muscle)
              Spacer()
              if isSelected {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $viewModel.showCamera) {
      CameraView(viewModel: viewModel)
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK", role: .cancel) {
        viewModel.showError = false
      }
    } message: {
      Text(viewModel.errorMessage)
    }
    .onChange(of: viewModel.shouldNavigateToProfile) { shouldNavigate in
      if shouldNavigate {
        presentationMode.wrappedValue.dismiss()
      }
    }
    .onTapGesture {
      focusedField = nil
    }
  }
}

struct KeyboardToolbar: View {
  var onDone: () -> Void

  var body: some View {
    VStack {
      Spacer()
      HStack {
        Spacer()
        Button("Done") {
          onDone()
        }
        .padding(.trailing)
      }
      .frame(height: 44)
      .background(Color(UIColor.systemBackground))
      .overlay(
        Rectangle()
          .frame(height: 0.5)
          .foregroundColor(Color(UIColor.separator)),
        alignment: .top
      )
    }
    .edgesIgnoringSafeArea(.bottom)
  }
}
