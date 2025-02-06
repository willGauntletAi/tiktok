import PhotosUI
import SwiftUI

struct VideoSelectionView: View {
  @Binding var videoThumbnail: UIImage?
  @Binding var showCamera: Bool
  @State private var selectedItem: PhotosPickerItem?
  @State private var isChangingVideo: Bool = false
  let onVideoSelected: (PhotosPickerItem) async -> Void

  var body: some View {
    VStack(spacing: 20) {
      GroupBox(label: Text("Video").bold()) {
        ZStack {
          if let videoPreview = videoThumbnail {
            Image(uiImage: videoPreview)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxWidth: .infinity)
              .frame(height: 200)
              .clipped()
              .transition(.opacity)
          } else {
            Rectangle()
              .fill(Color.gray.opacity(0.2))
              .frame(maxWidth: .infinity)
              .frame(height: 200)
              .overlay(
                Text("No video selected")
                  .foregroundColor(.gray)
              )
          }
        }
        .animation(.easeInOut, value: videoThumbnail)
      }
      .padding(.horizontal)

      GroupBox(label: Text("Record or Select Video").bold()) {
        VStack(spacing: 12) {
          Button(action: { showCamera = true }) {
            HStack {
              Image(systemName: "camera")
                .frame(width: 24, height: 24)
              Text(videoThumbnail == nil ? "Record New Video" : "Record Different Video")
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundColor(.gray)
            }
          }
          .padding(.vertical, 8)
          .disabled(isChangingVideo)

          Divider()

          PhotosPicker(
            selection: $selectedItem,
            matching: .videos
          ) {
            HStack {
              Image(systemName: "photo.on.rectangle")
                .frame(width: 24, height: 24)
              Text(
                isChangingVideo
                  ? "Adding Video..."
                  : (videoThumbnail == nil ? "Select from Library" : "Choose Different Video")
              )
              Spacer()
              if isChangingVideo {
                Image(systemName: "chevron.right")
                  .foregroundColor(.gray)
              }
            }
            .foregroundColor(isChangingVideo ? .gray : .primary)
          }
          .disabled(isChangingVideo)
          .onChange(of: selectedItem) { newValue in
            if let item = newValue {
              withAnimation {
                isChangingVideo = true
                videoThumbnail = nil
              }

              Task {
                await onVideoSelected(item)
                withAnimation {
                  isChangingVideo = false
                }
                selectedItem = nil
              }
            }
          }
          .padding(.vertical, 8)
        }
      }
      .padding(.horizontal)
    }
  }
}
