import AVKit
import PhotosUI
import SwiftUI

struct VideoTimelineView: View {
    @ObservedObject var viewModel: VideoEditViewModel
    @Binding var currentPosition: Double
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: Int?
    @State private var isLoadingThumbnails = true
    @State private var totalWidth: CGFloat = 0
    @State private var isDragging = false
    @State private var dragPosition: Double = 0
    @State private var seekTask: Task<Void, Never>?

    private let thumbnailHeight: CGFloat = 60
    private let positionIndicatorWidth: CGFloat = 2
    private let swapButtonSize: CGFloat = 24

    var body: some View {
        VStack(spacing: 12) {
            if !viewModel.clips.isEmpty {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Timeline background
                        Rectangle()
                            .fill(Color.black.opacity(0.2))
                            .frame(height: thumbnailHeight)
                        
                        // Seek gesture overlay
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: thumbnailHeight)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                                        let newPosition = progress * viewModel.totalDuration
                                        dragPosition = newPosition
                                        seekToTime(newPosition)
                                    }
                                    .onEnded { value in
                                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                                        let newPosition = progress * viewModel.totalDuration
                                        currentPosition = newPosition
                                        dragPosition = newPosition
                                        seekToTime(newPosition)
                                        isDragging = false
                                    }
                            )
                            .allowsHitTesting(true)
                        
                        // Clips thumbnails with buttons on top
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
                                            .allowsHitTesting(false)  // Let seek gesture handle taps
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(
                                                width: clipWidth(for: clip, in: geometry.size.width),
                                                height: thumbnailHeight
                                            )
                                            .allowsHitTesting(false)  // Let seek gesture handle taps
                                    }

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
                                        .allowsHitTesting(true)  // Ensure button remains tappable

                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                    // Add swap button if this isn't the last clip
                                    if index < viewModel.clips.count - 1 {
                                        Button(action: {
                                            viewModel.swapClips(at: index)
                                        }) {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .frame(width: swapButtonSize, height: swapButtonSize)
                                                .background(Circle().fill(Color.blue))
                                                .foregroundColor(.white)
                                        }
                                        .offset(x: swapButtonSize / 2)
                                        .allowsHitTesting(true)  // Ensure button remains tappable
                                    }
                                }
                            }
                        }

                        // Position indicator
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: positionIndicatorWidth, height: thumbnailHeight + 20)
                            .offset(
                                x: geometry.size.width
                                    * CGFloat(
                                        (isDragging ? dragPosition : currentPosition) / max(viewModel.totalDuration, 0.001)
                                    ),
                                y: -10
                            )
                            .shadow(radius: 2)
                            .allowsHitTesting(false)  // Don't let indicator block gestures
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
            startPositionTimer()
        }
        .onDisappear {
            seekTask?.cancel()
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

    private func seekToTime(_ time: Double) {
        guard let player = viewModel.player else { return }
        let targetTime = CMTime(seconds: time, preferredTimescale: 600)
        
        Task {
            await player.seek(
                to: targetTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    private func startPositionTimer() {
        // Create a timer that updates every 1/30th of a second
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [self] timer in
            Task { @MainActor in
                guard !isDragging,
                      let player = viewModel.player else { return }
                currentPosition = player.currentTime().seconds
            }
        }
        
        // Make sure timer continues to fire when scrolling
        RunLoop.current.add(timer, forMode: .common)
    }

    private func clipWidth(for clip: VideoClip, in totalWidth: CGFloat) -> CGFloat {
        let clipDuration = clip.endTime - clip.startTime
        let totalDuration = viewModel.totalDuration
        guard totalDuration > 0 else { return 0 }
        
        // Calculate proportional width based on duration
        return totalWidth * CGFloat(clipDuration / totalDuration)
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
    @State private var selectedItem: PhotosPickerItem?
    @State private var isAddingClip = false
    @State private var showCamera = false
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
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                        .allowsHitTesting(true)
                        .zIndex(0)
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

                // Action buttons
                ZStack {
                    HStack(spacing: 12) {
                        // Camera button
                        Button("Record") {
                            print("Camera button tapped")
                            showCamera = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isAddingClip)

                        // Library button
                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .videos,
                            photoLibrary: .shared()
                        ) {
                            Text(isAddingClip ? "Adding..." : "Add Clip")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isAddingClip || viewModel.isProcessing)

                        // Split button
                        if !viewModel.clips.isEmpty {
                            Button("Split") {
                                print("Split button tapped at position: \(viewModel.currentPosition)")
                                Task { @MainActor in
                                    print("Starting split operation...")
                                    await viewModel.splitClip(at: viewModel.currentPosition)
                                    print("Split operation completed")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(viewModel.currentPosition <= 0 || 
                                     viewModel.currentPosition >= viewModel.totalDuration || 
                                     isAddingClip || 
                                     viewModel.isProcessing)
                        }
                    }
                    .padding(.horizontal)
                }
                .zIndex(2)

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
        .onChange(of: selectedItem) { oldValue, newValue in
            if let item = newValue {
                print("Starting to process selected item")
                Task {
                    isAddingClip = true
                    print("isAddingClip set to true")
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            print("Successfully loaded transferable data")
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension("mov")

                            do {
                                try data.write(to: tempURL)
                                print("Successfully wrote data to temp file: \(tempURL)")
                                try await viewModel.addClip(from: tempURL)
                                print("Successfully added clip to viewModel")
                            } catch {
                                print("Error adding clip: \(error.localizedDescription)")
                                print("Error details: \(error)")
                            }
                        } else {
                            print("Failed to load transferable data")
                        }
                    } catch {
                        print("Error loading transferable: \(error.localizedDescription)")
                        print("Error details: \(error)")
                    }
                    selectedItem = nil
                    isAddingClip = false
                    print("Finished processing selected item, isAddingClip set to false")
                }
            }
        }
    }
}

#Preview {
    VideoEditView()
}
