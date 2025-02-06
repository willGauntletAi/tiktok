import AVKit
import PhotosUI
import SwiftUI

struct VideoTimelineView: View {
    @ObservedObject var viewModel: VideoEditViewModel
    @Binding var currentPosition: Double
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: Int?
    @State private var isLoadingThumbnails = true
    @State private var totalWidth: CGFloat = 0
    @State private var isDragging = false
    @State private var dragPosition: Double = 0
    @State private var seekTask: Task<Void, Never>?
    @State private var isAddingClip = false
    @State private var showCamera = false
    @StateObject private var cameraViewModel = CreateExerciseViewModel()

    private let thumbnailHeight: CGFloat = 60
    private let positionIndicatorWidth: CGFloat = 2
    private let swapButtonSize: CGFloat = 24

    var body: some View {
        VStack(spacing: 12) {
            // Add clip buttons
            HStack {
                // Camera button
                Button(action: { showCamera = true }) {
                    Label("Record", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isAddingClip)

                // Library button
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos
                ) {
                    Label(
                        isAddingClip ? "Adding Clip..." : "Add Clip", systemImage: isAddingClip ? "" : "plus"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isAddingClip ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isAddingClip)

                if !viewModel.clips.isEmpty {
                    Button(action: {
                        Task {
                            await viewModel.splitClip(at: currentPosition)
                        }
                    }) {
                        Label("Split", systemImage: "scissors")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(
                        currentPosition <= 0 || currentPosition >= viewModel.totalDuration || isAddingClip)
                }
            }
            .padding(.horizontal)

            if !viewModel.clips.isEmpty {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Timeline background and gesture detector
                        Rectangle()
                            .fill(Color.black.opacity(0.2))
                            .frame(height: thumbnailHeight)
                            .contentShape(Rectangle()) // Make entire area tappable
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
                            ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                                ZStack(alignment: .trailing) {
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
                                                        lineWidth: 2
                                                    )
                                            )
                                            .onTapGesture {
                                                viewModel.selectedClipIndex = index
                                            }
                                            .allowsHitTesting(false) // Let gestures pass through thumbnails

                                        // Delete button
                                        VStack {
                                            Button(action: {
                                                clipToDelete = index
                                                showingDeleteAlert = true
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Circle().fill(Color.white))
                                                    .padding(4)
                                            }
                                            .zIndex(2) // Ensure button appears above everything

                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    }

                                    // Add swap button if this isn't the last clip and has non-zero width
                                    if index < viewModel.clips.count - 1
                                        && clipWidth(for: clip, in: geometry.size.width) > 0
                                    {
                                        Button(action: {
                                            viewModel.swapClips(at: index)
                                        }) {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .frame(width: swapButtonSize, height: swapButtonSize)
                                                .background(Circle().fill(Color.blue))
                                                .foregroundColor(.white)
                                        }
                                        .offset(x: swapButtonSize / 2)
                                        .zIndex(2) // Ensure button appears above everything
                                    }
                                }
                            }
                        }
                        .allowsHitTesting(true) // Allow interaction with buttons

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
                            .allowsHitTesting(false) // Let gestures pass through
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
                    isAddingClip = true
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
                    isAddingClip = false
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ZStack {
                if let currentFrame = cameraViewModel.currentFrame {
                    Image(currentFrame, scale: 1.0, label: Text("Camera Preview"))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                }

                VStack {
                    Spacer()

                    HStack(spacing: 30) {
                        Spacer()

                        // Record button
                        Button(action: {
                            if cameraViewModel.isRecording {
                                cameraViewModel.stopRecording()
                            } else {
                                cameraViewModel.startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 3)
                                    .frame(width: 72, height: 72)

                                Circle()
                                    .fill(cameraViewModel.isRecording ? Color.red : Color.white)
                                    .frame(width: 60, height: 60)
                            }
                        }

                        // Cancel button
                        Button(action: { showCamera = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                Task {
                    do {
                        try await cameraViewModel.configureAndStartCaptureSession()
                    } catch {
                        print("Error setting up camera: \(error)")
                    }
                }
            }
            .onChange(of: cameraViewModel.videoData) { newData in
                if let data = newData {
                    Task {
                        isAddingClip = true
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("mov")

                        try? data.write(to: tempURL)
                        try await viewModel.addClip(from: tempURL)
                        showCamera = false
                        isAddingClip = false
                    }
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
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay

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
        let totalDuration = viewModel.totalDuration
        guard totalDuration > 0 else { return 0 }
        return max(0, totalWidth * CGFloat(clipDuration / totalDuration))
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
                            player.play() // Start playing when view appears
                        }
                        .onDisappear {
                            player.pause() // Pause when view disappears
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
                VideoTimelineView(viewModel: viewModel, currentPosition: $viewModel.currentPosition)
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
}

#Preview {
    VideoEditView()
}
