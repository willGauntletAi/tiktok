import SwiftUI
import FirebaseFunctions

struct SongGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tags: String = ""
    @State private var lyrics: String = ""
    @State private var title: String = ""
    @State private var isGenerating = false
    @State private var error: String?
    
    var onSongGenerated: ((String) -> Void)?
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Form {
                        Section {
                            TextField("Title (optional)", text: $title)
                            
                            TextField("Tags (comma separated)", text: $tags)
                                .textInputAutocapitalization(.never)
                        }
                        
                        Section {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $lyrics)
                                    .frame(height: geometry.size.height * 0.5)
                                    .scrollContentBackground(.hidden)
                                
                                if lyrics.isEmpty {
                                    Text("Enter lyrics here...")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                        } header: {
                            Text("Lyrics")
                        }
                        
                        if let error = error {
                            Section {
                                Text(error)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Section {
                            Button(action: generateSong) {
                                if isGenerating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Text("Generate Song")
                                }
                            }
                            .disabled(isGenerating || lyrics.isEmpty || tags.isEmpty)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Generate Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func generateSong() {
        isGenerating = true
        error = nil
        
        let tagsList = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let data: [String: Any] = [
            "tags": tagsList,
            "lyrics": lyrics,
            "title": title.isEmpty ? nil : title
        ].compactMapValues { $0 }
        
        Functions.functions().httpsCallable("generateSong")
            .call(data) { result, error in
                isGenerating = false
                
                if let error = error {
                    self.error = error.localizedDescription
                    return
                }
                
                if let data = result?.data as? [String: Any],
                   let songData = data["data"] as? [String: Any],
                   let storageRef = songData["storageRef"] as? String {
                    onSongGenerated?(storageRef)
                    dismiss()
                } else {
                    self.error = "Failed to parse response"
                }
            }
    }
}

#Preview {
    SongGenerationView()
} 