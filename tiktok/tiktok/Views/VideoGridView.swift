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
    NavigationStack(path: $navigator.path) {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 1) {
          ForEach(videos) { video in
            NavigationLink(
              destination: VideoDetailView(
                workoutPlan: WorkoutPlan(
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
                          )
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
                    )
                  ],
                  duration: 1,
                  createdAt: video.createdAt,
                  updatedAt: video.updatedAt
                ),
                workoutIndex: 0,
                exerciseIndex: 0
              )
            ) {
              VideoThumbnailView(video: video)
                .frame(height: UIScreen.main.bounds.width / 3)
            }
          }
        }
        .padding(.horizontal, 1)
      }
      .navigationDestination(for: AppRoute.self) { route in
        switch route {
        case .profile:
          ProfileView()
        case .userProfile(let userId):
          ProfileView(userId: userId)
        }
      }
    }
  }
}
