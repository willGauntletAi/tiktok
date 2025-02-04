import SwiftUI

struct FindVideoView<T: Identifiable & EmptyInitializable>: View where T.ID: Hashable {
  @StateObject private var viewModel: FindVideoViewModel<T>
  @FocusState private var focusedField: Field?
  var onItemSelected: ((T) -> Void)?
  var selectedIds: Set<String>
  var type: String
  var title: String

  init(
    type: String, title: String, onItemSelected: ((T) -> Void)? = nil, selectedIds: Set<String> = []
  ) {
    self._viewModel = StateObject(wrappedValue: FindVideoViewModel<T>(type: type))
    self.onItemSelected = onItemSelected
    self.selectedIds = selectedIds
    self.type = type
    self.title = title
  }

  enum Field {
    case instructorEmail
    case title
  }

  private func isItemSelected(_ item: T) -> Bool {
    let idString = String(describing: item.id)
    return selectedIds.contains(idString)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Search Fields
      VStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 0) {
          TextField("Instructor Email", text: $viewModel.instructorEmail)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .focused($focusedField, equals: .instructorEmail)
            .submitLabel(.next)
            .onChange(of: viewModel.instructorEmail) { _ in
              Task {
                await viewModel.searchEmails()
              }
            }
            .onChange(of: focusedField) { field in
              viewModel.isEmailFocused = (field == .instructorEmail)
              if field == .instructorEmail {
                Task {
                  await viewModel.searchEmails()
                }
              } else {
                viewModel.emailSuggestions = []
              }
            }

          // Email Suggestions
          if viewModel.isEmailFocused
            && (!viewModel.instructorEmail.isEmpty || !viewModel.emailSuggestions.isEmpty)
          {
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.emailSuggestions, id: \.self) { email in
                  Button(action: { viewModel.selectEmail(email) }) {
                    Text(email)
                      .padding(.vertical, 8)
                      .padding(.horizontal, 12)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .buttonStyle(.plain)

                  if email != viewModel.emailSuggestions.last {
                    Divider()
                  }
                }
              }
            }
            .frame(maxHeight: 200)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
          }
        }

        TextField("\(type) Title", text: $viewModel.searchText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .focused($focusedField, equals: .title)
          .submitLabel(.search)
      }
      .padding()
      .background(Color(.systemBackground))
      .onSubmit {
        switch focusedField {
        case .instructorEmail:
          focusedField = .title
        case .title:
          focusedField = nil
          Task {
            await viewModel.search()
          }
        case .none:
          break
        }
      }

      // Results
      ScrollView {
        if viewModel.isLoading {
          ProgressView()
            .padding()
        } else if let error = viewModel.errorMessage {
          Text(error)
            .foregroundColor(.red)
            .padding()
        } else if viewModel.items.isEmpty {
          Text("No \(type.lowercased())s found")
            .foregroundColor(.gray)
            .padding()
        } else {
          LazyVStack(spacing: 16) {
            ForEach(viewModel.items) { item in
              if let onSelect = onItemSelected {
                // Selection mode
                VideoResultCard(
                  item: item,
                  type: type,
                  isSelected: isItemSelected(item),
                  onToggle: onSelect
                )
                .padding(.horizontal)
              } else {
                // Regular view mode
                NavigationLink(destination: VideoDetailView(item: item, type: type)) {
                  VideoCard(item: item, type: type)
                    .padding(.horizontal)
                }
              }
            }
          }
          .padding(.vertical)
        }
      }
    }
    .background(
      Color(.systemBackground)
        .onTapGesture {
          focusedField = nil
        }
    )
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: viewModel.searchText) { _ in
      Task {
        await viewModel.search()
      }
    }
    .onAppear {
      viewModel.selectedIds = selectedIds
    }
  }
}

struct VideoResultCard<T>: View {
  let item: T
  let type: String
  let isSelected: Bool
  let onToggle: (T) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VideoCard(item: item, type: type)

      Button(action: { onToggle(item) }) {
        HStack {
          Image(systemName: isSelected ? "minus.circle.fill" : "plus.circle.fill")
          Text(isSelected ? "Remove from \(type)" : "Add to \(type)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.red : Color.blue)
        .foregroundColor(.white)
        .cornerRadius(8)
      }
    }
    .padding(12)
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
  }
}

struct VideoCard<T>: View {
  let item: T
  let type: String

  var body: some View {
    HStack(spacing: 16) {
      AsyncImage(
        url: URL(
          string: (item as? Exercise)?.thumbnailUrl ?? (item as? Workout)?.thumbnailUrl ?? "")
      ) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray
      }
      .frame(width: 80, height: 80)
      .cornerRadius(8)

      VStack(alignment: .leading, spacing: 4) {
        Text((item as? Exercise)?.title ?? (item as? Workout)?.title ?? "")
          .font(.headline)
          .lineLimit(2)

        Text((item as? Exercise)?.description ?? (item as? Workout)?.description ?? "")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      Spacer()
    }
  }
}
