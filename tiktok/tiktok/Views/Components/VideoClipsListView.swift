import PhotosUI
import SwiftUI

struct VideoClipsListView: View {
    @ObservedObject var viewModel: VideoEditViewModel
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: Int?

    var body: some View {
        HStack(spacing: 12) {
            // Add clip button
            PhotosPicker(
                selection: $selectedItem,
                matching: .videos
            ) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Clip")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            if !viewModel.clips.isEmpty {
                // Clips list
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.clips.indices, id: \.self) { index in
                            ClipThumbnailView(
                                clip: viewModel.clips[index],
                                isSelected: viewModel.selectedClipIndex == index,
                                onTap: { viewModel.selectedClipIndex = index },
                                onDelete: {
                                    clipToDelete = index
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 100)

                // Total duration
                Text(
                    String(
                        format: "Total Duration: %@",
                        timeString(from: viewModel.totalDuration)
                    )
                )
                .font(.caption)
                .foregroundColor(.gray)
            }
        }
        .onChange(of: selectedItem) { _, newValue in
            if let item = newValue {
                Task {
                    do {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("mov")

                            try? data.write(to: tempURL)
                            try await viewModel.addClip(from: tempURL)
                        }
                    } catch {
                        print("Error adding clip: \(error)")
                    }
                    selectedItem = nil
                }
            }
        }
        .alert("Delete Clip", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let index = clipToDelete {
                    viewModel.deleteClip(at: index)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this clip?")
        }
    }

    private func timeString(from seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ClipThumbnailView: View {
    let clip: VideoClip
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail = clip.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
                .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
    }
}
