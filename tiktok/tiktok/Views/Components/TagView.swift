import SwiftUI

struct TagView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.blue.opacity(0.1))
      .foregroundColor(.blue)
      .clipShape(Capsule())
  }
}

struct TagsView: View {
  let tags: [String]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(tags, id: \.self) { tag in
          TagView(text: tag)
        }
      }
      .padding(.horizontal, 4)
    }
  }
}
