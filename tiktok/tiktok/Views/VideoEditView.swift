import AVKit
import PhotosUI
import SwiftUI

struct VideoEditView: View {
  @StateObject private var viewModel = VideoEditViewModel()
  @State private var selectedItem: PhotosPickerItem?
  @State private var showingExportError = false
  @Environment(\.dismiss) private var dismiss
  var onVideoEdited: ((URL) -> Void)?

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {
        if viewModel.isProcessing {
          ProgressView("Processing video...")
            .progressViewStyle(CircularProgressViewStyle())
        } else if let player = viewModel.getPlayer() {
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
          // Video selection
          PhotosPicker(
            selection: $selectedItem,
            matching: .videos
          ) {
            VStack {
              Image(systemName: "video.badge.plus")
                .font(.system(size: 40))
              Text("Select Video")
                .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
          }
        }

        // Editing controls
        if let asset = viewModel.videoAsset {
          ScrollView {
            VStack(spacing: 24) {
              // Video trimmer
              GroupBox("Trim") {
                VStack(alignment: .leading, spacing: 8) {
                  VideoTrimmerView(
                    asset: asset,
                    startTime: $viewModel.startTime,
                    endTime: $viewModel.endTime,
                    duration: viewModel.duration
                  )

                  HStack {
                    Text(timeString(from: viewModel.startTime))
                    Spacer()
                    Text(timeString(from: viewModel.endTime))
                  }
                  .font(.caption)
                  .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
              }

              // Audio control
              GroupBox("Audio") {
                VStack(spacing: 4) {
                  HStack {
                    Image(systemName: "speaker.fill")
                    Slider(
                      value: $viewModel.volume,
                      in: 0...2)
                    Image(systemName: "speaker.wave.3.fill")
                  }
                  Text(String(format: "%.1fx", viewModel.volume))
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

        if viewModel.videoAsset != nil {
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
      .alert(
        "Export Error",
        isPresented: $showingExportError
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(viewModel.errorMessage ?? "Failed to export video")
      }
      .onChange(of: selectedItem) { item in
        if let item = item {
          Task {
            // Get the URL from the selected item
            if let data = try? await item.loadTransferable(type: Data.self) {
              let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

              try? data.write(to: tempURL)
              await viewModel.loadVideo(from: tempURL)
            }
          }
        }
      }
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
