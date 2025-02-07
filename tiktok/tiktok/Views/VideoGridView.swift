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
                ForEach(videos) { video in
                    let workoutPlan = WorkoutPlan(
                        id: UUID().uuidString,
                        title: video.title,
                        description: video.description,
                        instructorId: video.instructorId,
                        videoUrl: video.videoUrl,
                        thumbnailUrl: video.thumbnailUrl,
                        difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                        targetMuscles: video.targetMuscles,
                        workouts: [
                            WorkoutWithMetadata(
                                workout: Workout(
                                    id: UUID().uuidString,
                                    title: video.title,
                                    description: video.description,
                                    exercises: [
                                        Exercise(
                                            id: video.id,
                                            type: video.type.rawValue,
                                            title: video.title,
                                            description: video.description,
                                            instructorId: video.instructorId,
                                            videoUrl: video.videoUrl,
                                            thumbnailUrl: video.thumbnailUrl,
                                            difficulty: Difficulty(rawValue: video.difficulty.rawValue)
                                                ?? .beginner,
                                            targetMuscles: video.targetMuscles,
                                            duration: 0,
                                            createdAt: video.createdAt,
                                            updatedAt: video.updatedAt
                                        ),
                                    ],
                                    instructorId: video.instructorId,
                                    videoUrl: video.videoUrl,
                                    thumbnailUrl: video.thumbnailUrl,
                                    difficulty: Difficulty(rawValue: video.difficulty.rawValue) ?? .beginner,
                                    targetMuscles: video.targetMuscles,
                                    totalDuration: 0,
                                    createdAt: video.createdAt,
                                    updatedAt: video.updatedAt
                                ),
                                weekNumber: 1,
                                dayOfWeek: 1
                            ),
                        ],
                        duration: 1,
                        createdAt: video.createdAt,
                        updatedAt: video.updatedAt
                    )

                    VideoThumbnailView(video: video)
                        .frame(height: UIScreen.main.bounds.width / 3)
                        .onTapGesture {
                            navigator.navigate(to: .profileVideo(workoutPlan: workoutPlan))
                        }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
