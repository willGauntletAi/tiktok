import AVFoundation
import SwiftUI

struct VideoTrimmerView: View {
    let asset: AVAsset
    @Binding var startTime: Double
    @Binding var endTime: Double
    let duration: Double
    let thumbnailCount: Int = 10

    @State private var thumbnails: [UIImage] = []
    @State private var isLoadingThumbnails = true
    @State private var totalWidth: CGFloat = 0

    private let thumbnailHeight: CGFloat = 40
    private let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width

            ZStack(alignment: .leading) {
                // Timeline background
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(height: thumbnailHeight)

                // Thumbnails
                HStack(spacing: 0) {
                    if isLoadingThumbnails {
                        ForEach(0 ..< thumbnailCount, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: availableWidth / CGFloat(thumbnailCount), height: thumbnailHeight)
                        }
                    } else {
                        ForEach(thumbnails.indices, id: \.self) { index in
                            Image(uiImage: thumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: availableWidth / CGFloat(thumbnailCount), height: thumbnailHeight)
                                .clipped()
                        }
                    }
                }
                .frame(height: thumbnailHeight)

                // Selected range visualization
                ZStack {
                    // Left overlay (before start handle)
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: max(0, startHandlePosition(in: availableWidth)), height: thumbnailHeight)
                        .allowsHitTesting(false)

                    // Right overlay (after end handle)
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(
                            width: max(0, availableWidth - endHandlePosition(in: availableWidth)),
                            height: thumbnailHeight
                        )
                        .offset(x: endHandlePosition(in: availableWidth))
                        .allowsHitTesting(false)
                }

                // Start handle
                VideoTrimmerHandle()
                    .frame(width: handleWidth, height: thumbnailHeight + 20)
                    .position(
                        x: max(handleWidth / 2, startHandlePosition(in: availableWidth)),
                        y: thumbnailHeight / 2
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                updateStartTime(with: value.location.x, in: availableWidth)
                            }
                    )

                // End handle
                VideoTrimmerHandle()
                    .frame(width: handleWidth, height: thumbnailHeight + 20)
                    .position(
                        x: min(availableWidth - handleWidth / 2, endHandlePosition(in: availableWidth)),
                        y: thumbnailHeight / 2
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                updateEndTime(with: value.location.x, in: availableWidth)
                            }
                    )
            }
            .frame(height: thumbnailHeight)
            .onAppear {
                totalWidth = availableWidth
                generateThumbnails()
            }
            .onChange(of: geometry.size.width) { _, newValue in
                totalWidth = newValue
            }
        }
        .frame(height: thumbnailHeight)
    }

    private func startHandlePosition(in width: CGFloat) -> CGFloat {
        width * CGFloat(startTime / duration)
    }

    private func endHandlePosition(in width: CGFloat) -> CGFloat {
        width * CGFloat(endTime / duration)
    }

    private func updateStartTime(with xPosition: CGFloat, in width: CGFloat) {
        let newStartTime = Double(max(0, min(xPosition, width))) / Double(width) * duration
        startTime = min(max(0, newStartTime), endTime - 1)
    }

    private func updateEndTime(with xPosition: CGFloat, in width: CGFloat) {
        let newEndTime = Double(max(0, min(xPosition, width))) / Double(width) * duration
        endTime = max(min(duration, newEndTime), startTime + 1)
    }

    private func generateThumbnail(at time: CMTime, using generator: AVAssetImageGenerator)
        async throws -> UIImage
    {
        do {
            let result = try await generator.image(at: time)
            return UIImage(cgImage: result.image)
        } catch {
            throw error
        }
    }

    private func generateThumbnails() {
        Task {
            await MainActor.run { isLoadingThumbnails = true }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 160)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            // Create array of time points
            let timePoints = (0 ..< thumbnailCount).map { i in
                CMTime(
                    seconds: duration * Double(i) / Double(thumbnailCount),
                    preferredTimescale: 600
                )
            }

            do {
                // First ensure the asset is loaded
                _ = try await asset.load(.tracks)

                // Generate thumbnails concurrently
                let thumbnails = try await withThrowingTaskGroup(of: (Int, UIImage).self) { group in
                    for (index, time) in timePoints.enumerated() {
                        group.addTask {
                            let thumbnail = try await generateThumbnail(at: time, using: generator)
                            return (index, thumbnail)
                        }
                    }

                    var results: [(Int, UIImage)] = []
                    for try await result in group {
                        results.append(result)
                    }
                    return results.sorted { $0.0 < $1.0 }.map { $0.1 }
                }

                await MainActor.run {
                    self.thumbnails = thumbnails
                    self.isLoadingThumbnails = false
                }
            } catch {
                print("Failed to generate thumbnails: \(error)")
                await MainActor.run {
                    self.isLoadingThumbnails = false
                }
            }
        }
    }
}

struct VideoTrimmerHandle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .shadow(radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
    }
}

#Preview {
    VideoTrimmerView(
        asset: AVURLAsset(url: URL(string: "https://example.com/video.mp4")!),
        startTime: .constant(0),
        endTime: .constant(10),
        duration: 10
    )
    .padding()
}
