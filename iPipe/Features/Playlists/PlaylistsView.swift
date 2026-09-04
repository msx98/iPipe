import Foundation
import SwiftUI
import UIKit

/// Backing state for the playlists list screen.
@Observable
@MainActor
final class PlaylistsListModel {
    var showCreateAlert = false
    var newPlaylistName = ""
    var isEditing = false
    var pendingDeletePlaylist: LocalPlaylist?
    var deleteConfirmPresented = false

    /// Creates an empty playlist via the manager (empty name is rejected, but an
    /// empty stream list is allowed), then clears the prompt state.
    func createEmptyPlaylist(app: AppModel) {
        app.playlists.create(newPlaylistName, streams: [])
        newPlaylistName = ""
        showCreateAlert = false
    }

    /// Performs the confirmed deletion of the playlist read from the list.
    func deletePendingPlaylist(app: AppModel) {
        guard let playlist = pendingDeletePlaylist else { return }
        app.playlists.delete(playlist)
        pendingDeletePlaylist = nil
        deleteConfirmPresented = false
        if app.playlists.playlists.isEmpty { isEditing = false }
    }
}

/// Small trailing accessory shown on every playlists row: an "×" that removes the
/// row while editing, or a chevron when idle.
struct PlaylistRowAccessory: View {
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        if isEditing {
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Shared playlists row used by both the playlists home list and a playlist's
/// detail list. It standardizes the edit-mode affordances (a leading reorder
/// handle via a 180° flip of the native control, and a trailing "×"/chevron
/// accessory) so both screens behave identically. `onTap` is applied only to the
/// leading thumbnail/title so the trailing accessory stays independently
/// tappable; pass `nil` while editing.
struct PlaylistRowCell: View {
    let thumbnailURL: URL?
    let videoId: String
    let thumbnailWidth: CGFloat
    let title: String
    let subtitle: String
    let isEditing: Bool
    var titleBinding: Binding<String>? = nil
    var titleFont: Font = .subheadline.weight(.semibold)
    var subtitleFont: Font = .caption
    var onTap: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 0)
            PlaylistRowAccessory(isEditing: isEditing, onDelete: onDelete)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leading: some View {
        if let onTap {
            Button(action: onTap) {
                leadingContent
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            leadingContent
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        HStack(spacing: 12) {
            AsyncThumbnail(url: thumbnailURL, videoId: videoId)
                .frame(width: thumbnailWidth)
            VStack(alignment: .leading, spacing: 2) {
                titleView
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditing, let titleBinding {
            TextField("Name", text: titleBinding)
                .font(titleFont)
        } else {
            Text(title)
                .font(titleFont)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Top-level playlists screen: list of local playlists with an empty state,
/// swipe-to-delete, an edit mode (left reorder handle, "×" per row, rename the
/// name inline), and a "New" action that prompts for a name.
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
                        .onMove { offsets, destination in
                            app.playlists.move(from: offsets, to: destination)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(model.isEditing ? .active : .inactive))
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Theme.topBarButtonColor)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isEditing ? "Done" : "Edit") {
                        withAnimation { model.isEditing.toggle() }
                    }
                    .disabled(app.playlists.playlists.isEmpty)
                    .tint(Theme.topBarButtonColor)
                }
                StandardToolbar()
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
            .alert("Delete playlist?", isPresented: $model.deleteConfirmPresented) {
                Button("Delete", role: .destructive) {
                    model.deletePendingPlaylist(app: app)
                }
                Button("Cancel", role: .cancel) {
                    model.deleteConfirmPresented = false
                }
            } message: {
                Text("This playlist will be deleted.")
            }
            .navigationDestination(for: String.self) { playlistID in
                PlaylistDetailScreen(playlistID: playlistID)
            }
        }
    }

    @ViewBuilder
    private func playlistCell(_ playlist: LocalPlaylist) -> some View {
        PlaylistRowCell(
            thumbnailURL: playlist.thumbnailURL,
            videoId: playlist.streams.first?.id ?? "",
            thumbnailWidth: 96,
            title: playlist.name,
            subtitle: "\(playlist.streamCount) items · \(playlist.totalDuration.durationText)",
            isEditing: model.isEditing,
            titleBinding: Binding(
                get: { playlist.name },
                set: { newValue in
                    if !newValue.isEmpty { app.playlists.rename(playlist, to: newValue) }
                }
            ),
            onTap: model.isEditing ? nil : { app.playlistsPath.append(playlist.id) },
            onDelete: {
                model.pendingDeletePlaylist = playlist
                model.deleteConfirmPresented = true
            }
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.pendingDeletePlaylist = playlist
                model.deleteConfirmPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Backing state for a single playlist's detail screen.
@Observable
@MainActor
final class PlaylistDetailModel {
    var showShareSheet = false
    var shareText = ""
    var showRemoveWatchedConfirm = false
    var isWorking = false
    var pendingDeleteItem: LocalPlaylistItem?
    var removeItemDialogPresented = false
    var isEditing = false

    let playlistID: String

    init(playlistID: String) {
        self.playlistID = playlistID
    }

    /// Fetches the playlist currently stored in the manager (nil if gone).
    func refreshPlaylist(app: AppModel) -> LocalPlaylist? {
        app.playlists.playlists.first { $0.id == playlistID }
    }

    /// Performs the confirmed removal of an item read from the list.
    func deletePendingItem(app: AppModel) {
        guard let item = pendingDeleteItem, let playlist = refreshPlaylist(app: app) else { return }
        app.playlists.removeItem(item, from: playlist)
        pendingDeleteItem = nil
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

/// Detail screen for a single local playlist: header with an edit toggle, a Play
/// button, an ordered, reorderable list of its videos (leading reorder handle and
/// a trailing "×"/chevron), and a menu of playlist actions.
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
        .navigationTitle("")
        .toolbar { playlistToolbar }
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
        .alert("Remove from playlist?", isPresented: $model.removeItemDialogPresented) {
            Button("Remove", role: .destructive) {
                model.deletePendingItem(app: app)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This video will be removed from the playlist.")
        }
    }

    @ViewBuilder
    private func detailContent(_ playlist: LocalPlaylist) -> some View {
        List {
            Section {
                headerRow(playlist)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                playAllButton
                    .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(Array(playlist.streams.enumerated()), id: \.element.id) { index, item in
                    PlaylistRowCell(
                        thumbnailURL: item.stream.thumbnailURL,
                        videoId: item.stream.id,
                        thumbnailWidth: 140,
                        title: item.stream.title,
                        subtitle: item.stream.author,
                        isEditing: model.isEditing,
                        onTap: model.isEditing ? nil : {
                            app.focusedVideo = item.stream
                            Task { await model.playItem(at: index, app: app) }
                        },
                        onDelete: {
                            model.pendingDeleteItem = item
                            model.removeItemDialogPresented = true
                        }
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.pendingDeleteItem = item
                            model.removeItemDialogPresented = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
                .onMove { offsets, destination in
                    app.playlists.moveItem(from: offsets, to: destination, in: playlist)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(model.isEditing ? .active : .inactive))
        .overlay(alignment: .center) {
            if model.isWorking {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func headerRow(_ playlist: LocalPlaylist) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { model.isEditing.toggle() }
            } label: {
                Image(systemName: model.isEditing ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(playlist.streamCount) items · \(playlist.totalDuration.durationText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var playAllButton: some View {
        Button {
            Task { await model.playAll(app: app) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Play")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .disabled(model.isEditing || (playlist?.streams.isEmpty ?? true))
    }

    private var playlistToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task { await model.playAll(app: app) }
                } label: {
                    Label("Play all", systemImage: "play.fill")
                }
                .disabled(model.isEditing || (playlist?.streams.isEmpty ?? true))

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
            .tint(Theme.topBarButtonColor)
        }
    }
}
