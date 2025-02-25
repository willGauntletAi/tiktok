import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import SwiftUI

struct MuscleSelectorView: View {
    let muscleGroups: [String]
    @Binding var selectedMuscles: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(muscleGroups, id: \.self) { muscle in
                let isSelected = selectedMuscles.contains(muscle)
                Button(action: {
                    if isSelected {
                        selectedMuscles.removeAll { $0 == muscle }
                    } else {
                        selectedMuscles.append(muscle)
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
            .navigationTitle("Select Muscles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CreateExerciseView: View {
    @StateObject private var viewModel = CreateExerciseViewModel()
    @State private var showingMuscleSelector = false
    @State private var showVideoEditor = false
    @State private var selectedVideoForEdit: PhotosPickerItem?
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigator: Navigator
    let onComplete: () -> Void

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
                    VStack {
                        if viewModel.isUploading {
                            ProgressView("Uploading video...")
                                .progressViewStyle(CircularProgressViewStyle())
                        } else if let thumbnail = viewModel.videoThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipped()
                        } else {
                            Button(action: { showVideoEditor = true }) {
                                VStack {
                                    Image(systemName: "video.badge.plus")
                                        .font(.system(size: 40))
                                    Text("Add Video")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }

                        if viewModel.videoThumbnail != nil {
                            Button(action: { showVideoEditor = true }) {
                                Text("Change Video")
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 8)
                        }
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
                            .lineLimit(3 ... 6)
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.navigator = navigator
            viewModel.dismiss = onComplete
        }
        .sheet(isPresented: $showingMuscleSelector) {
            MuscleSelectorView(
                muscleGroups: muscleGroups,
                selectedMuscles: $viewModel.exercise.targetMuscles
            )
        }
        .sheet(isPresented: $showVideoEditor) {
            VideoEditView { url in
                Task {
                    let data = try? Data(contentsOf: url)
                    if let data = data {
                        await viewModel.processVideoData(data)
                    }
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {
                viewModel.showError = false
            }
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
