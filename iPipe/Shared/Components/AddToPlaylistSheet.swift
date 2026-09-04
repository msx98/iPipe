import SwiftUI

/// Reusable "Add to playlist" sheet content. Presents the user's playlists and a
/// "New Playlist…" row; appending a stream into a playlist (or creating a new one).
struct AddToPlaylistSheet: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    @Environment(\.dismiss) private var dismiss
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            List {
                if app.playlists.playlists.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(app.playlists.playlists) { playlist in
                        Button {
                            app.playlists.append([stream], to: playlist)
                            dismiss()
                        } label: {
                            HStack {
                                Label(playlist.name, systemImage: "list.bullet")
                                    .font(.footnote)
                                    .lineLimit(1)
                                Spacer()
                                if playlist.streams.contains(where: { $0.stream.id == stream.id }) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                Button {
                    newPlaylistName = ""
                    showNewPlaylistAlert = true
                } label: {
                    Label("New Playlist…", systemImage: "plus.rectangle.on.folder")
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    app.playlists.create(newPlaylistName, streams: [stream])
                    dismiss()
                    newPlaylistName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium])
    }
}