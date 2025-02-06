import SwiftUI

struct FindVideoView<T: VideoContent>: View where T.ID: Hashable {
    @StateObject private var viewModel: FindVideoViewModel<T>
    @StateObject private var authService = AuthService.shared
    @FocusState private var focusedField: Field?
    @State private var navigationPath = NavigationPath()
    let onItemSelected: ((T) -> Void)?
    let selectedIds: Set<String>
    let type: String
    let title: String
    let actionButtonTitle: ((String) -> String)?

    enum Field {
        case instructorEmail
        case title
    }

    init(
        type: String,
        title: String,
        onItemSelected: ((T) -> Void)? = nil,
        selectedIds: Set<String> = [],
        actionButtonTitle: ((String) -> String)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: FindVideoViewModel<T>(type: type))
        self.onItemSelected = onItemSelected
        self.selectedIds = selectedIds
        self.type = type
        self.title = title
        self.actionButtonTitle = actionButtonTitle
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
                                    Button(action: { Task { await viewModel.selectEmail(email) } }) {
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

    struct ResultsList: View {
        let items: [T]
        let type: String
        let selectedIds: Set<String>
        let onToggle: (T) -> Void
        let actionButtonTitle: ((String) -> String)?
        @Binding var navigationPath: NavigationPath

        var body: some View {
            LazyVStack(spacing: 16) {
                ForEach(items) { item in
                    VideoResultCard(
                        video: item,
                        isSelected: selectedIds.contains(String(describing: item.id)),
                        onToggle: onToggle,
                        addToType: type,
                        actionButtonTitle: actionButtonTitle
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("Tapped item: \(item.id)")
                        navigationPath.append(item)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                            selectedIds: selectedIds,
                            onToggle: { item in
                                onItemSelected?(item)
                            },
                            actionButtonTitle: actionButtonTitle,
                            navigationPath: $navigationPath
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
                if let currentUserEmail = authService.currentUser?.email {
                    Task {
                        await viewModel.selectEmail(currentUserEmail)
                    }
                }
            }
            .navigationDestination(for: T.self) { item in
                VideoDetailView(
                    workoutPlan: WorkoutPlan(
                        id: UUID().uuidString,
                        title: item.title,
                        description: item.description,
                        instructorId: item.instructorId,
                        videoUrl: item.videoUrl,
                        thumbnailUrl: item.thumbnailUrl,
                        difficulty: item.difficulty,
                        targetMuscles: item.targetMuscles,
                        workouts: [
                            WorkoutWithMetadata(
                                workout: Workout(
                                    id: UUID().uuidString,
                                    title: item.title,
                                    description: item.description,
                                    exercises: type == "exercise" ? [item as! Exercise] : [],
                                    instructorId: item.instructorId,
                                    videoUrl: item.videoUrl,
                                    thumbnailUrl: item.thumbnailUrl,
                                    difficulty: item.difficulty,
                                    targetMuscles: item.targetMuscles,
                                    totalDuration: (item as? Exercise)?.duration ?? 0,
                                    createdAt: item.createdAt,
                                    updatedAt: item.updatedAt
                                ),
                                weekNumber: 1,
                                dayOfWeek: 1
                            ),
                        ],
                        duration: 1,
                        createdAt: item.createdAt,
                        updatedAt: item.updatedAt
                    ),
                    workoutIndex: 0,
                    exerciseIndex: type == "exercise" ? 0 : nil
                )
            }
        }
    }
}

struct VideoResultCard<T: VideoContent>: View {
    let video: T
    let isSelected: Bool
    let onToggle: (T) -> Void
    let addToType: String
    let actionButtonTitle: ((String) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoCard(exercise: video)

            Button(action: {
                onToggle(video)
            }) {
                HStack {
                    Image(systemName: isSelected ? "plus.circle.fill" : "plus.circle.fill")
                    Text(
                        actionButtonTitle?(String(describing: video.id))
                            ?? (isSelected ? "Add Again" : "Add to \(addToType)"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    // Stop event propagation
                })
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
