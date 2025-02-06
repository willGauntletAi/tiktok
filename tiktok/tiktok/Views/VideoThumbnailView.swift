import SwiftUI

struct VideoThumbnailView: View {
    let video: ProfileViewModel.Video

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.gray.opacity(0.2)
                        ProgressView()
                    }

                case let .success(image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                case .failure:
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.gray)
                    }

                @unknown default:
                    Color.gray.opacity(0.2)
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(video.type.rawValue.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
            }
        }
    }
}
