import SwiftUI

struct AIPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VideoEditViewModel
    @State private var prompt: String = ""
    @State private var isLoading = false
    @State private var showingPoseDetectionAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Ask AI to suggest edits")
                    .font(.headline)
                    .padding(.top)

                Text("Describe what kind of improvement you're looking for, and the AI will suggest specific edits to enhance your video.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("E.g., Make the video more engaging", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button(action: {
                    Task {
                        isLoading = true
                        await viewModel.requestAIEditSuggestion(prompt: prompt)
                        // If we need to wait for user decision about pose detection
                        if viewModel.shouldWaitForPoseDetection == nil {
                            showingPoseDetectionAlert = true
                            isLoading = false
                            return
                        }
                        isLoading = false
                        dismiss()
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Get Suggestions")
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty || isLoading)

                Spacer()
            }
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .alert("Pose Detection In Progress", isPresented: $showingPoseDetectionAlert) {
                Button("Wait for Detection", role: .none) {
                    Task {
                        viewModel.shouldWaitForPoseDetection = true
                        isLoading = true
                        await viewModel.requestAIEditSuggestion(prompt: prompt)
                        isLoading = false
                        dismiss()
                    }
                }
                Button("Proceed Without Detection", role: .none) {
                    Task {
                        viewModel.shouldWaitForPoseDetection = false
                        isLoading = true
                        await viewModel.requestAIEditSuggestion(prompt: prompt)
                        isLoading = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.shouldWaitForPoseDetection = false
                }
            } message: {
                Text("Some clips are still being analyzed for exercise detection. Would you like to wait for the analysis to complete? This will help the AI make better suggestions about exercise timing and transitions.")
            }
        }
    }
}

#Preview {
    AIPromptView(viewModel: VideoEditViewModel())
}
