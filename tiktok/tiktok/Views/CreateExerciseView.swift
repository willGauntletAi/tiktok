import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore

struct CreateExerciseView: View {
    @StateObject private var viewModel = CreateExerciseViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingMuscleSelector = false
    
    let muscleGroups = [
        "Chest", "Back", "Shoulders", "Biceps", "Triceps",
        "Legs", "Core", "Full Body"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Video") {
                    if let videoPreview = viewModel.videoThumbnail {
                        Image(uiImage: videoPreview)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                    }
                }
                
                Section("Record or Select Video") {
                    Button(action: { viewModel.showCamera = true }) {
                        HStack {
                            Image(systemName: "camera")
                                .frame(width: 24, height: 24)
                            Text(viewModel.videoThumbnail == nil ? "Record New Video" : "Record Different Video")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    PhotosPicker(selection: $selectedItem,
                               matching: .videos) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .frame(width: 24, height: 24)
                            Text(viewModel.videoThumbnail == nil ? "Select from Library" : "Choose Different Video")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .onChange(of: selectedItem) { newValue in
                        Task {
                            await viewModel.loadVideo(from: newValue)
                        }
                    }
                }
                
                Section("Details") {
                    TextField("Title", text: $viewModel.exercise.title)
                    TextField("Description", text: $viewModel.exercise.description, axis: .vertical)
                    Picker("Difficulty", selection: $viewModel.exercise.difficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.rawValue.capitalized)
                        }
                    }
                }
                
                Section("Target Muscles") {
                    Button(action: { showingMuscleSelector = true }) {
                        HStack {
                            Text("Select Muscles")
                            Spacer()
                            Text("\(viewModel.exercise.targetMuscles.count) selected")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section("Exercise Specifics") {
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("Seconds", value: $viewModel.exercise.duration, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Sets")
                        Spacer()
                        TextField("Optional", value: $viewModel.exercise.sets, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("Optional", value: $viewModel.exercise.reps, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button(action: { Task { await viewModel.uploadExercise() } }) {
                        HStack {
                            Spacer()
                            Text("Upload Exercise")
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.canUpload)
                }
            }
            .navigationTitle("Create Exercise")
            .sheet(isPresented: $showingMuscleSelector) {
                NavigationView {
                    List(muscleGroups, id: \.self) { muscle in
                        let isSelected = viewModel.exercise.targetMuscles.contains(muscle)
                        HStack {
                            Text(muscle)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                viewModel.exercise.targetMuscles.removeAll { $0 == muscle }
                            } else {
                                viewModel.exercise.targetMuscles.append(muscle)
                            }
                        }
                    }
                    .navigationTitle("Select Muscles")
                    .navigationBarItems(trailing: Button("Done") {
                        showingMuscleSelector = false
                    })
                }
            }
            .fullScreenCover(isPresented: $viewModel.showCamera) {
                CameraView(viewModel: viewModel)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
} 