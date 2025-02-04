import AVKit
import SwiftUI

struct ExerciseDetailView: View {
  let exercise: Exercise
  @State private var player: AVPlayer?
  @Environment(\.dismiss) private var dismiss
  @GestureState private var dragOffset = CGSize.zero

  var body: some View {
    ZStack {
      // Video Player
      if let player = player {
        VideoPlayer(player: player)
          .edgesIgnoringSafeArea(.all)
      }

      // Description overlay at bottom
      VStack {
        Spacer()
        Text(exercise.description)
          .lineLimit(1)
          .padding()
          .frame(maxWidth: .infinity)
          .background(.ultraThinMaterial)
      }
    }
    .navigationBarHidden(true)
    .gesture(
      DragGesture()
        .updating($dragOffset) { value, state, _ in
          state = value.translation
        }
        .onEnded { value in
          if value.translation.width > 100 {
            dismiss()
          }
        }
    )
    .onAppear {
      if let url = URL(string: exercise.videoUrl) {
        player = AVPlayer(url: url)
        player?.play()
      }
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }
}
