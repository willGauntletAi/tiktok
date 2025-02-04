import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct CreateExerciseView: View {
  @StateObject private var viewModel = CreateExerciseViewModel()
  @State private var selectedItem: PhotosPickerItem?
  @State private var showingMuscleSelector = false
  @State private var isChangingVideo = false
  @FocusState private var focusedField: Field?

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
        GroupBox(label: Text("Video").bold()) {
          ZStack {
            if isChangingVideo {
              Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .overlay(
                  ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                )
                .transition(.opacity)
            } else if let videoPreview = viewModel.videoThumbnail {
              Image(uiImage: videoPreview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .transition(.opacity)
            } else {
              Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .overlay(
                  Text("No video selected")
                    .foregroundColor(.gray)
                )
            }
          }
          .animation(.easeInOut, value: isChangingVideo)
          .animation(.easeInOut, value: viewModel.videoThumbnail)
        }
        .padding(.horizontal)

        GroupBox(label: Text("Record or Select Video").bold()) {
          VStack(spacing: 12) {
            Button(action: { viewModel.showCamera = true }) {
              HStack {
                Image(systemName: "camera")
                  .frame(width: 24, height: 24)
                Text(
                  viewModel.videoThumbnail == nil ? "Record New Video" : "Record Different Video")
                Spacer()
                Image(systemName: "chevron.right")
                  .foregroundColor(.gray)
              }
            }
            .padding(.vertical, 8)

            Divider()

            PhotosPicker(
              selection: $selectedItem,
              matching: .videos
            ) {
              HStack {
                Image(systemName: "photo.on.rectangle")
                  .frame(width: 24, height: 24)
                Text(
                  viewModel.videoThumbnail == nil
                    ? "Select from Library" : "Choose Different Video")
                Spacer()
                Image(systemName: "chevron.right")
                  .foregroundColor(.gray)
              }
            }
            .onChange(of: selectedItem) { newValue in
              if let item = newValue {
                withAnimation {
                  isChangingVideo = true
                  viewModel.videoThumbnail = nil
                }

                Task {
                  await viewModel.loadVideo(from: item)
                  withAnimation {
                    isChangingVideo = false
                  }
                  selectedItem = nil
                }
              }
            }
            .padding(.vertical, 8)
          }
        }
        .padding(.horizontal)

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
          Text("Upload Exercise")
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.canUpload ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(!viewModel.canUpload)
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
    .fullScreenCover(isPresented: $viewModel.showCamera) {
      CameraView(viewModel: viewModel)
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
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
