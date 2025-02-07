import SwiftUI

struct VideoGridView: View {
    let videos: [ProfileViewModel.Video]
    @EnvironmentObject private var navigator: Navigator

    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                    VideoThumbnailView(video: video)
                        .frame(height: UIScreen.main.bounds.width / 3)
                        .onTapGesture {
                            // Convert all videos to VideoContent array
                            let allVideos = videos.map { video -> (any VideoContent) in
                                Exercise(
                                    id: video.id,
                                    type: video.type.rawValue,
                                    title: video.title,
                                    description: video.description,
                                    instructorId: video.instructorId,
                                    videoUrl: video.videoUrl,
                                    thumbnailUrl: video.thumbnailUrl,
                                    difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                                    targetMuscles: video.targetMuscles,
                                    duration: 0,
                                    createdAt: video.createdAt,
                                    updatedAt: video.updatedAt
                                )
                            }
                            navigator.navigate(to: .videoDetail(videos: allVideos, startIndex: index))
                        }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
