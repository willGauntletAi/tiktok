import SwiftUI

struct FindVideoView<T: VideoContent>: View where T.ID: Hashable {
  @StateObject private var viewModel: FindVideoViewModel<T>
  @FocusState private var focusedField: Field?
  let onItemSelected: ((T) -> Void)?
  let selectedIds: Set<String>
  let type: String
  let title: String

  enum Field {
    case instructorEmail
    case title
  }

  init(
    type: String,
    title: String,
    onItemSelected: ((T) -> Void)? = nil,
    selectedIds: Set<String> = []
  ) {
    self._viewModel = StateObject(wrappedValue: FindVideoViewModel<T>(type: type))
    self.onItemSelected = onItemSelected
    self.selectedIds = selectedIds
    self.type = type
    self.title = title
  }

  struct SearchSection<C: VideoContent>: View {
    @ObservedObject var viewModel: FindVideoViewModel<T>
    @FocusState var focusedField: Field?
    let type: String

    var body: some View {
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

          if viewModel.isEmailFocused
            && (!viewModel.instructorEmail.isEmpty || !viewModel.emailSuggestions.isEmpty)
          {
            // Email Suggestions
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
    }
  }

  struct ResultsList<C: VideoContent>: View {
    let items: [C]
    let type: String
    let selectedIds: Set<String>

    var body: some View {
      LazyVStack(spacing: 16) {
        ForEach(items) { item in
          NavigationLink(value: item) {
            VideoResultCard(
              video: item,
              isSelected: selectedIds.contains(String(describing: item.id)),
              onToggle: { _ in },
              addToType: type
            )
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      .padding(.vertical)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      SearchSection<T>(
        viewModel: viewModel,
        focusedField: _focusedField,
        type: type
      )

      // Results Section
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
          ResultsList(
            items: viewModel.items,
            type: type,
            selectedIds: selectedIds
          )
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
    .navigationDestination(for: T.self) { item in
      VideoDetailView(item: item, type: type)
    }
  }
}

struct VideoResultCard<C: VideoContent>: View {
  let video: C
  let isSelected: Bool
  let onToggle: (C) -> Void
  let addToType: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VideoCard(exercise: video)

      Button(action: { onToggle(video) }) {
        HStack {
          Image(systemName: isSelected ? "minus.circle.fill" : "plus.circle.fill")
          Text(isSelected ? "Remove from \(addToType)" : "Add to \(addToType)")
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
