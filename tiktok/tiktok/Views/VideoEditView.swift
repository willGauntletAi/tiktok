import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var isAddingClip: Bool
    let onVideoSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        // Request high performance delivery mode
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func picker(_: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false

            guard let provider = results.first?.itemProvider else {
                // If no video was selected, reset the isAddingClip state
                DispatchQueue.main.async {
                    self.parent.isAddingClip = false
                }
                return
            }

            // Set isAddingClip to true as soon as a video is selected
            DispatchQueue.main.async {
                self.parent.isAddingClip = true
            }

            // Create a unique temporary file URL
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            // First try to get the video file URL directly
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                // Try to load as AVURLAsset first for better performance
                provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] item, error in
                    guard let self = self else { return }

                    if let error = error {
                        print("Error loading video: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.parent.isAddingClip = false
                        }
                        return
                    }

                    if let videoURL = item as? URL {
                        // Copy the file to our temporary location
                        do {
                            if FileManager.default.fileExists(atPath: tempURL.path) {
                                try FileManager.default.removeItem(at: tempURL)
                            }
                            try FileManager.default.copyItem(at: videoURL, to: tempURL)

                            DispatchQueue.main.async {
                                self.parent.onVideoSelected(tempURL)
                            }
                        } catch {
                            print("Error copying video: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.parent.isAddingClip = false
                            }
                        }
                    } else if let videoData = item as? Data {
                        // If we got data directly, write it to the file
                        do {
                            try videoData.write(to: tempURL)
                            DispatchQueue.main.async {
                                self.parent.onVideoSelected(tempURL)
                            }
                        } catch {
                            print("Error writing video data: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.parent.isAddingClip = false
                            }
                        }
                    } else {
                        // Fallback to file representation if direct methods fail
                        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                            if let error = error {
                                print("Error loading video file: \(error.localizedDescription)")
                                DispatchQueue.main.async {
                                    self.parent.isAddingClip = false
                                }
                                return
                            }

                            guard let url = url else {
                                DispatchQueue.main.async {
                                    self.parent.isAddingClip = false
                                }
                                return
                            }

                            do {
                                if FileManager.default.fileExists(atPath: tempURL.path) {
                                    try FileManager.default.removeItem(at: tempURL)
                                }
                                try FileManager.default.copyItem(at: url, to: tempURL)

                                DispatchQueue.main.async {
                                    self.parent.onVideoSelected(tempURL)
                                }
                            } catch {
                                print("Error copying video: \(error.localizedDescription)")
                                DispatchQueue.main.async {
                                    self.parent.isAddingClip = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct VideoClipContextMenu: View {
    let clip: VideoClip
    let index: Int
    let viewModel: VideoEditViewModel
    @Binding var selectedClipForZoom: Int?
    @Binding var showZoomDialog: Bool
    @Binding var clipToDelete: Int?
    @Binding var showingDeleteAlert: Bool

    var body: some View {
        Button(action: {
            selectedClipForZoom = index
            showZoomDialog = true
        }) {
            Label("Add/Edit Zoom", systemImage: "plus.magnifyingglass")
        }

        if clip.zoomConfig != nil {
            Button(role: .destructive, action: {
                viewModel.updateZoomConfig(at: index, config: nil)
            }) {
                Label("Remove Zoom", systemImage: "minus.magnifyingglass")
            }
        }

        Divider()

        Button(role: .destructive, action: {
            clipToDelete = index
            showingDeleteAlert = true
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct VideoTimelineView: View {
    @ObservedObject var viewModel: VideoEditViewModel
    @Binding var currentPosition: Double
    @State private var showingDeleteAlert = false
    @State private var clipToDelete: Int?
    @State private var isLoadingThumbnails = true
    @State private var showZoomDialog = false
    @State private var selectedClipForZoom: Int?

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
                            .allowsHitTesting(false)

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
                                            .contextMenu {
                                                VideoClipContextMenu(
                                                    clip: clip,
                                                    index: index,
                                                    viewModel: viewModel,
                                                    selectedClipForZoom: $selectedClipForZoom,
                                                    showZoomDialog: $showZoomDialog,
                                                    clipToDelete: $clipToDelete,
                                                    showingDeleteAlert: $showingDeleteAlert
                                                )
                                            }
                                    } else {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(
                                                width: clipWidth(for: clip, in: geometry.size.width),
                                                height: thumbnailHeight
                                            )
                                    }

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
                                    }
                                }
                            }
                        }

                        // Position indicator (read-only)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: positionIndicatorWidth, height: thumbnailHeight + 20)
                            .offset(
                                x: geometry.size.width * CGFloat(currentPosition / max(viewModel.totalDuration, 0.001)),
                                y: -10
                            )
                            .shadow(radius: 2)
                    }
                }
                .frame(height: thumbnailHeight)

                // Time indicators
                HStack {
                    Text(timeString(from: currentPosition))
                    Spacer()
                    Text(timeString(from: viewModel.totalDuration))
                }
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.horizontal)
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
        .sheet(isPresented: $showZoomDialog) {
            if let index = selectedClipForZoom,
               index < viewModel.clips.count
            {
                let clip = viewModel.clips[index]
                ZoomDialog(
                    clipDuration: clip.assetDuration,
                    existingConfig: clip.zoomConfig
                ) { config in
                    viewModel.updateZoomConfig(at: index, config: config)
                }
            }
        }
    }

    private func clipWidth(for clip: VideoClip, in totalWidth: CGFloat) -> CGFloat {
        let clipDuration = clip.assetDuration
        let totalDuration = viewModel.totalDuration
        guard totalDuration > 0 else { return 0 }

        // Calculate proportional width based on duration
        return totalWidth * CGFloat(clipDuration / totalDuration)
    }

    private func timeString(from seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else {
            return "0:00"
        }

        let minutes = Int(max(0, seconds)) / 60
        let seconds = Int(max(0, seconds)) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No edit history yet")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
}

struct HistoryEntryView: View {
    let entry: EditHistoryEntry
    let index: Int
    let currentHistoryIndex: Int
    let onUndo: (Int) async -> Void
    let onRedo: (Int) async -> Void
    
    var body: some View {
        Button(action: {
            Task {
                if index <= currentHistoryIndex {
                    // When undoing, we want to go to the state before this action
                    await onUndo(index - 1)
                } else {
                    // When redoing, we want to apply this action
                    await onRedo(index)
                }
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let prompt = entry.prompt {
                        Text(prompt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: index <= currentHistoryIndex ? "arrow.uturn.backward" : "arrow.uturn.forward")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(.systemBackground))
    }
}

struct EditHistoryView: View {
    @ObservedObject var viewModel: VideoEditViewModel
    @State private var prompt: String = ""
    @State private var isSubmitting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Prompt input section
            VStack(spacing: 8) {
                TextField("Enter your editing suggestion...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                Button(action: {
                    guard !prompt.isEmpty else { return }
                    isSubmitting = true
                    
                    Task {
                        await viewModel.requestAIEditSuggestion(prompt: prompt)
                        prompt = "" // Clear the prompt after submission
                        isSubmitting = false
                    }
                }) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                        Text(isSubmitting ? "Processing..." : "Get AI Suggestion")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty || isSubmitting)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemBackground))
            
            Divider()
            
            // History list
            if viewModel.editHistory.isEmpty {
                EmptyHistoryView()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.editHistory.enumerated()).reversed(), id: \.element.id) { index, entry in
                        HistoryEntryView(
                            entry: entry,
                            index: index,
                            currentHistoryIndex: viewModel.currentHistoryIndex,
                            onUndo: { targetIndex in
                                await viewModel.undo(to: targetIndex)
                            },
                            onRedo: { targetIndex in
                                await viewModel.redo(to: targetIndex)
                            }
                        )
                        
                        if index > 0 {
                            Divider()
                        }
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}

struct VideoEditView: View {
    @StateObject private var viewModel = VideoEditViewModel()
    @State private var showingExportError = false
    @State private var isAddingClip = false
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var showSongGeneration = false
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss
    
    var onVideoEdited: ((URL) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.isProcessing {
                            ProgressView("Processing video...")
                                .progressViewStyle(CircularProgressViewStyle())
                        } else if let player = viewModel.player, viewModel.selectedClip != nil {
                            // Video preview with native AVKit controls
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
                                .zIndex(1)
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
                                Button(isAddingClip ? "Adding..." : "Add Clip") {
                                    showVideoPicker = true
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

                        // Content based on selected tab
                        Group {
                            if selectedTab == 0 {
                                VideoTimelineView(viewModel: viewModel, currentPosition: $viewModel.currentPosition)
                                    .frame(height: 160)
                            } else {
                                EditHistoryView(viewModel: viewModel)
                            }
                        }
                        .padding(.bottom, 50) // Add padding for the tab bar
                    }
                    .padding(.vertical)
                }

                // Custom tab bar at the bottom
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        Spacer()
                        Button(action: { selectedTab = 0 }) {
                            VStack {
                                Image(systemName: "film")
                                Text("Timeline")
                            }
                            .foregroundColor(selectedTab == 0 ? .blue : .gray)
                        }
                        Spacer()
                        Button(action: { selectedTab = 1 }) {
                            VStack {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("History")
                            }
                            .foregroundColor(selectedTab == 1 ? .blue : .gray)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                .shadow(radius: 2, y: -2)
                .ignoresSafeArea(.all, edges: .bottom)
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
                                    let url = try await viewModel.export()
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
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(isPresented: $showVideoPicker, isAddingClip: $isAddingClip) { url in
                Task { @MainActor in
                    do {
                        try await viewModel.addClip(from: url)
                        isAddingClip = false
                    } catch {
                        print("Error adding clip: \(error.localizedDescription)")
                        isAddingClip = false
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(onVideoRecorded: { url in
                Task { @MainActor in
                    do {
                        try await viewModel.addClip(from: url)
                    } catch {
                        print("Error adding recorded clip: \(error.localizedDescription)")
                    }
                }
            })
        }
        .sheet(isPresented: $showSongGeneration) {
            SongGenerationView { storageRef in
                // Handle the generated song
                print("Generated song at: \(storageRef)")
                // TODO: Add the song to the video
            }
        }
        // Add shake gesture support
        .onShake {
            Task {
                await viewModel.undo(to: nil) // Use default behavior to undo most recent action
            }
        }
    }
}

// Add shake gesture detection
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

// SwiftUI shake gesture view modifier
struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(DeviceShakeViewModifier(action: action))
    }
}

#Preview {
    VideoEditView()
}
