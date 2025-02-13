import SwiftUI

struct AIPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VideoEditViewModel
    @State private var prompt: String = ""
    @State private var isLoading = false

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
        }
    }
}

#Preview {
    AIPromptView(viewModel: VideoEditViewModel())
}
