import Foundation
import SwiftUI
import UIKit

/// Backing state for the playlists list screen.
@Observable
@MainActor
final class PlaylistsListModel {
    var showCreateAlert = false
    var newPlaylistName = ""

    /// Creates an empty playlist via the manager (empty name is rejected, but an
    /// empty stream list is allowed), then clears the prompt state.
    func createEmptyPlaylist(app: AppModel) {
        app.playlists.create(newPlaylistName, streams: [])
        newPlaylistName = ""
        showCreateAlert = false
    }
}

/// Top-level playlists screen: list of local playlists with an empty state,
/// swipe-to-delete, and a "New" action that prompts for a name.
struct PlaylistsView: View {
    @Environment(AppModel.self) private var app
    @State private var model = PlaylistsListModel()

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.playlistsPath) {
            Group {
                if app.playlists.playlists.isEmpty {
                    ContentUnavailableView(
                        "No playlists yet",
                        systemImage: "list.bullet",
                        description: Text("Add videos from any video page.")
                    )
                } else {
List {
                        ForEach(app.playlists.playlists) { playlist in
                            playlistCell(playlist)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Playlist", isPresented: $model.showCreateAlert) {
                TextField("Name", text: $model.newPlaylistName)
                Button("Create") {
                    model.createEmptyPlaylist(app: app)
                }
                Button("Cancel", role: .cancel) {
                    model.showCreateAlert = false
                }
            }
            .navigationDestination(for: String.self) { playlistID in
                PlaylistDetailScreen(playlistID: playlistID)
            }
        }
    }

    @ViewBuilder
    private func playlistCell(_ playlist: LocalPlaylist) -> some View {
        NavigationLink(value: playlist.id) {
            playlistRow(playlist)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                app.playlists.delete(playlist)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func playlistRow(_ playlist: LocalPlaylist) -> some View {
        HStack(spacing: 12) {
            AsyncThumbnail(url: playlist.thumbnailURL, videoId: playlist.streams.first?.id ?? "")
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(playlist.streamCount) items · \(playlist.totalDuration.durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// Backing state for a single playlist's detail screen.
@Observable
@MainActor
final class PlaylistDetailModel {
    var showRenameAlert = false
    var newName = ""
    var showShareSheet = false
    var shareText = ""
    var showRemoveWatchedConfirm = false
    var isWorking = false
    var isEditing = false

    let playlistID: String

    init(playlistID: String) {
        self.playlistID = playlistID
    }

    /// Fetches the playlist currently stored in the manager (nil if gone).
    func refreshPlaylist(app: AppModel) -> LocalPlaylist? {
        app.playlists.playlists.first { $0.id == playlistID }
    }

    func rename(to name: String, app: AppModel) {
        guard let playlist = refreshPlaylist(app: app) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        app.playlists.rename(playlist, to: trimmed)
        showRenameAlert = false
    }

    func removeDuplicates(app: AppModel) async {
        guard let playlist = refreshPlaylist(app: app) else { return }
        isWorking = true
        app.playlists.removeDuplicates(from: playlist)
        isWorking = false
    }

    func removeWatched(app: AppModel) {
        guard let playlist = refreshPlaylist(app: app) else { return }
        let watchedIDs = Set(app.history.map { $0.id })
        app.playlists.removeWatched(in: playlist, watchedIDs: watchedIDs)
        showRemoveWatchedConfirm = false
    }

    /// Resolves every playlist item (capped at 100) to a playable queue element,
    /// fetching details concurrently and skipping failures while preserving order.
    func buildQueue(app: AppModel) async -> [QueueItem] {
        guard let playlist = refreshPlaylist(app: app) else { return [] }
        let capped = Array(playlist.streams.prefix(100))
        var indexed: [Int: QueueItem] = [:]
        await withTaskGroup(of: (Int, QueueItem?).self) { group in
            for (index, item) in capped.enumerated() {
                group.addTask {
                    do {
                        let details = try await app.extraction.streamDetails(id: item.stream.id)
                        return (index, QueueItem(stream: details.stream, formats: details.formats, prefer: nil))
                    } catch {
                        return (index, nil)
                    }
                }
            }
            for await (index, queueItem) in group {
                if let queueItem { indexed[index] = queueItem }
            }
        }
        return indexed.sorted { $0.key < $1.key }.map { $0.value }
    }

    func playAll(app: AppModel) async {
        let queue = await buildQueue(app: app)
        if !queue.isEmpty {
            app.player.playQueue(queue)
        }
    }

    /// Fills the latent queue with the whole playlist and starts it at the
    /// tapped item, so backgrounding the playlist leaves it as “up next”.
    func playItem(at index: Int, app: AppModel) async {
        guard let playlist = refreshPlaylist(app: app) else { return }
        let queue = await buildQueue(app: app)
        guard index < queue.count else { return }
        app.player.playQueue(queue, startAt: index)
    }

    func export(app: AppModel) {
        guard let playlist = refreshPlaylist(app: app) else { return }
        shareText = app.playlists.export(playlist, mode: .withTitles)
        showShareSheet = true
    }
}

/// Detail screen for a single local playlist: header with rename, an ordered,
/// reorderable/reorderable list of its videos, and a menu of playlist actions.
struct PlaylistDetailScreen: View {
    @Environment(AppModel.self) private var app
    let playlistID: String
    @State private var model: PlaylistDetailModel

    init(playlistID: String) {
        self.playlistID = playlistID
        _model = State(initialValue: PlaylistDetailModel(playlistID: playlistID))
    }

    var playlist: LocalPlaylist? {
        app.playlists.playlists.first { $0.id == playlistID }
    }

    private var hasWatched: Bool {
        guard let currentPlaylist = playlist else { return false }
        return currentPlaylist.streams.contains { item in
            app.history.contains { $0.id == item.stream.id }
        }
    }

    var body: some View {
        Group {
            if let currentPlaylist = playlist {
                if currentPlaylist.streams.isEmpty {
                    ContentUnavailableView(
                        "Empty Playlist",
                        systemImage: "list.bullet",
                        description: Text("Add videos from any video page to build this playlist.")
                    )
                } else {
                    detailContent(currentPlaylist)
                }
            } else {
                ContentUnavailableView(
                    "Playlist unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This playlist no longer exists.")
                )
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar { playlistToolbar }
        .navigationDestination(for: StreamItem.self) { VideoDetailView(stream: $0) }
        .alert("Rename Playlist", isPresented: $model.showRenameAlert) {
            TextField("Name", text: $model.newName)
            Button("Save") {
                model.rename(to: model.newName, app: app)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $model.showShareSheet) {
            ShareSheet(items: [model.shareText])
        }
        .alert("Remove watched videos", isPresented: $model.showRemoveWatchedConfirm) {
            Button("Remove") {
                model.removeWatched(app: app)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove videos you've already watched from this playlist?")
        }
    }

    @ViewBuilder
    private func detailContent(_ playlist: LocalPlaylist) -> some View {
        List {
            Section {
                headerCard(playlist)
            }
            Section {
                ForEach(Array(playlist.streams.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.stream) {
                        streamRow(item.stream)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        Task { await model.playItem(at: index, app: app) }
                    })
                }
                .onMove { offsets, destination in
                    app.playlists.moveItem(from: offsets, to: destination, in: playlist)
                }
                .onDelete { offsets in
                    let items = offsets.map { playlist.streams[$0] }
                    for item in items {
                        app.playlists.removeItem(item, from: playlist)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(model.isEditing ? .active : .inactive))
        .overlay(alignment: .center) {
            if model.isWorking {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func headerCard(_ playlist: LocalPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.newName = playlist.name
                model.showRenameAlert = true
            } label: {
                Text(playlist.name)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("\(playlist.streamCount) items · \(playlist.totalDuration.durationText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func streamRow(_ stream: StreamItem) -> some View {
        HStack(spacing: 12) {
            AsyncThumbnail(url: stream.thumbnailURL, videoId: stream.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(stream.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var playlistToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(model.isEditing ? "Done" : "Edit") {
                model.isEditing.toggle()
            }

            Menu {
                Button {
                    Task { await model.playAll(app: app) }
                } label: {
                    Label("Play all", systemImage: "play.fill")
                }
                .disabled(playlist?.streams.isEmpty ?? true)

                Button {
                    if let name = playlist?.name {
                        model.newName = name
                    }
                    model.showRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    Task { await model.removeDuplicates(app: app) }
                } label: {
                    Label("Remove duplicates", systemImage: "minus.forward.slash.plus")
                }

                if hasWatched {
                    Button {
                        model.showRemoveWatchedConfirm = true
                    } label: {
                        Label("Remove watched", systemImage: "clock.arrow.circlepath")
                    }
                }

                Button {
                    model.export(app: app)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                if let currentPlaylist = playlist {
                    Button(role: .destructive) {
                        app.playlists.delete(currentPlaylist)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }
}
