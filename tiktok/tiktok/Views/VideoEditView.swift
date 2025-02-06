import AVKit
import PhotosUI
import SwiftUI

struct VideoTimelineView: View {
  @ObservedObject var viewModel: VideoEditViewModel
  @State private var selectedItem: PhotosPickerItem?
  @State private var showingDeleteAlert = false
  @State private var clipToDelete: Int?
  @State private var isLoadingThumbnails = true
  @State private var totalWidth: CGFloat = 0
  @State private var currentPosition: Double = 0
  @State private var isDragging = false
  @State private var dragPosition: Double = 0
  @State private var seekTask: Task<Void, Never>?

  private let thumbnailHeight: CGFloat = 60
  private let positionIndicatorWidth: CGFloat = 2

  var body: some View {
    VStack(spacing: 12) {
      // Add clip button
      PhotosPicker(
        selection: $selectedItem,
        matching: .videos
      ) {
        Label("Add Clip", systemImage: "plus")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(8)
      }
      .padding(.horizontal)

      if !viewModel.clips.isEmpty {
        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            // Timeline background and gesture detector
            Rectangle()
              .fill(Color.black.opacity(0.2))
              .frame(height: thumbnailHeight)
              .contentShape(Rectangle())  // Make entire area tappable
              .gesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { value in
                    isDragging = true
                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                    dragPosition = progress * viewModel.totalDuration
                    debouncedSeek(to: dragPosition)
                  }
                  .onEnded { value in
                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                    let time = progress * viewModel.totalDuration
                    currentPosition = time
                    seekToTime(time)
                    isDragging = false
                  }
              )

            // Clips thumbnails
            HStack(spacing: 0) {
              ForEach(viewModel.clips.indices, id: \.self) { index in
                let clip = viewModel.clips[index]
                if let thumbnail = clip.thumbnail {
                  Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                      width: clipWidth(for: clip, in: geometry.size.width),
                      height: thumbnailHeight
                    )
                    .clipped()
                    .overlay(
                      Rectangle()
                        .stroke(
                          viewModel.selectedClipIndex == index ? Color.blue : Color.clear,
                          lineWidth: 2)
                    )
                    .onTapGesture {
                      viewModel.selectedClipIndex = index
                    }
                    .overlay(alignment: .topTrailing) {
                      // Delete button
                      Button(action: {
                        clipToDelete = index
                        showingDeleteAlert = true
                      }) {
                        Image(systemName: "xmark.circle.fill")
                          .foregroundColor(.red)
                          .background(Circle().fill(Color.white))
                          .padding(4)
                      }
                    }
                }
              }
            }
            .allowsHitTesting(false)  // Let gestures pass through to background

            // Position indicator
            Rectangle()
              .fill(Color.white)
              .frame(width: positionIndicatorWidth, height: thumbnailHeight + 20)
              .offset(
                x: geometry.size.width
                  * CGFloat(
                    (isDragging ? dragPosition : currentPosition) / viewModel.totalDuration
                  ),
                y: -10
              )
              .shadow(radius: 2)
              .allowsHitTesting(false)  // Let gestures pass through
          }
        }
        .frame(height: thumbnailHeight)

        // Time indicators
        HStack {
          Text(timeString(from: isDragging ? dragPosition : currentPosition))
          Spacer()
          Text(timeString(from: viewModel.totalDuration))
        }
        .font(.caption)
        .foregroundColor(.gray)
        .padding(.horizontal)
      }
    }
    .onAppear {
      // Start timer to update position
      startPositionTimer()
    }
    .onDisappear {
      seekTask?.cancel()
    }
    .onChange(of: selectedItem) { item in
      if let item = item {
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

  private func debouncedSeek(to time: Double) {
    // Cancel any existing seek task
    seekTask?.cancel()

    // Create a new task that waits briefly before seeking
    seekTask = Task {
      try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay

      if !Task.isCancelled {
        await MainActor.run {
          seekToTime(time)
        }
      }
    }
  }

  private func startPositionTimer() {
    // Create a timer that updates every 1/30th of a second
    Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
      if !isDragging, let player = viewModel.player {
        currentPosition = player.currentTime().seconds
      }
    }
  }

  private func seekToTime(_ time: Double) {
    guard let player = viewModel.player else { return }
    Task {
      await player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
  }

  private func clipWidth(for clip: VideoClip, in totalWidth: CGFloat) -> CGFloat {
    let clipDuration = clip.endTime - clip.startTime
    return totalWidth * CGFloat(clipDuration / viewModel.totalDuration)
  }

  private func timeString(from seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let seconds = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

struct VideoEditView: View {
  @StateObject private var viewModel = VideoEditViewModel()
  @State private var showingExportError = false
  @Environment(\.dismiss) private var dismiss
  var onVideoEdited: ((URL) -> Void)?

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        if viewModel.isProcessing {
          ProgressView("Processing video...")
            .progressViewStyle(CircularProgressViewStyle())
        } else if let player = viewModel.player, viewModel.selectedClip != nil {
          // Video preview
          VideoPlayer(player: player)
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .onAppear {
              player.play()  // Start playing when view appears
            }
            .onDisappear {
              player.pause()  // Pause when view disappears
            }
        } else {
          // Initial state - show clips list
          Text("Add clips to start editing")
            .font(.headline)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }

        // Timeline with position indicator
        VideoTimelineView(viewModel: viewModel)

        // Editing controls for selected clip
        if let clip = viewModel.selectedClip {
          ScrollView {
            VStack(spacing: 24) {
              // Audio control
              GroupBox("Audio") {
                VStack(spacing: 4) {
                  HStack {
                    Image(systemName: "speaker.fill")
                    Slider(
                      value: Binding(
                        get: { clip.volume },
                        set: { viewModel.updateClipVolume($0) }
                      ),
                      in: 0...2)
                    Image(systemName: "speaker.wave.3.fill")
                  }
                  Text(String(format: "%.1fx", clip.volume))
                    .font(.caption)
                    .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
              }

              // Video adjustments
              GroupBox("Adjustments") {
                VStack(spacing: 16) {
                  VStack(spacing: 4) {
                    HStack {
                      Image(systemName: "sun.min.fill")
                      Slider(
                        value: $viewModel.brightness,
                        in: -1...1)
                      Image(systemName: "sun.max.fill")
                    }
                    Text(String(format: "Brightness: %.1f", viewModel.brightness))
                      .font(.caption)
                      .foregroundColor(.gray)
                  }

                  VStack(spacing: 4) {
                    HStack {
                      Image(systemName: "circle.slash")
                      Slider(
                        value: $viewModel.contrast,
                        in: 0...2)
                      Image(systemName: "circle")
                    }
                    Text(String(format: "Contrast: %.1f", viewModel.contrast))
                      .font(.caption)
                      .foregroundColor(.gray)
                  }

                  VStack(spacing: 4) {
                    HStack {
                      Image(systemName: "drop.fill")
                      Slider(
                        value: $viewModel.saturation,
                        in: 0...2)
                      Image(systemName: "drop.fill").foregroundColor(.blue)
                    }
                    Text(String(format: "Saturation: %.1f", viewModel.saturation))
                      .font(.caption)
                      .foregroundColor(.gray)
                  }
                }
                .padding(.vertical, 8)
              }
            }
            .padding()
          }
        }
      }
      .navigationTitle("Edit Video")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            viewModel.cleanup()
            dismiss()
          }
        }

        if !viewModel.clips.isEmpty {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Export") {
              Task {
                do {
                  let url = try await viewModel.exportVideo()
                  onVideoEdited?(url)
                  dismiss()
                } catch {
                  viewModel.errorMessage = error.localizedDescription
                  showingExportError = true
                }
              }
            }
            .disabled(viewModel.isProcessing)
          }
        }
      }
    }
    .interactiveDismissDisabled()
    .alert(
      "Export Error",
      isPresented: $showingExportError
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage ?? "Failed to export video")
    }
  }

  private func timeString(from seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let seconds = Int(seconds) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

#Preview {
  VideoEditView()
}
