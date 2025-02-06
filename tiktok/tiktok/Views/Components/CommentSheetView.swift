import SwiftUI

struct CommentSheetView: View {
  @StateObject var viewModel: CommentViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Comment Input
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            TextField("Add a comment...", text: $viewModel.newCommentText)
              .textFieldStyle(.roundedBorder)

            Button {
              Task {
                await viewModel.postComment()
              }
            } label: {
              Image(systemName: "paperplane.fill")
                .foregroundColor(.blue)
            }
            .disabled(
              viewModel.isLoading
                || viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          .padding()

          Divider()
        }
        .background(Color(uiColor: .systemBackground))

        // Comments List
        ScrollView {
          LazyVStack(spacing: 16) {
            ForEach(viewModel.comments) { comment in
              CommentRow(comment: comment)
                .padding(.horizontal)
            }
          }
          .padding(.top)
        }
      }
      .navigationTitle("Comments")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .task {
        await viewModel.fetchComments()
      }
      .overlay {
        if viewModel.isLoading {
          ProgressView()
        }
      }
      .alert("Error", isPresented: .constant(viewModel.error != nil)) {
        Button("OK") {
          viewModel.error = nil
        }
      } message: {
        if let error = viewModel.error {
          Text(error)
        }
      }
    }
  }
}

struct CommentRow: View {
  let comment: Comment

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("@\(comment.userDisplayName)")
          .font(.subheadline)
          .fontWeight(.semibold)

        Spacer()

        Text(comment.createdAt, style: .relative)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Text(comment.content)
        .font(.body)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
