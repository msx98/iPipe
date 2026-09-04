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
    var showRenameAlert = false
    var newName = ""
    var renameTarget: LocalPlaylist?

    /// Creates an empty playlist via the manager (empty name is rejected, but an
    /// empty stream list is allowed), then clears the prompt state.
    func createEmptyPlaylist(app: AppModel) {
        app.playlists.create(newPlaylistName, streams: [])
        newPlaylistName = ""
        showCreateAlert = false
    }

    /// Starts the rename prompt, pre-filled with the playlist's current name.
    func beginRename(_ playlist: LocalPlaylist) {
        renameTarget = playlist
        newName = playlist.name
        showRenameAlert = true
    }

    /// Applies the confirmed rename to the target playlist via the manager.
    func commitRename(app: AppModel) {
        guard let target = renameTarget else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        app.playlists.rename(target, to: trimmed)
        renameTarget = nil
        showRenameAlert = false
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
/// detail list. It standardizes the edit-mode affordances (the native reorder
/// handle and a trailing "×"/chevron accessory) so both screens behave
/// identically. `onTap` is applied only to the leading thumbnail/title so the
/// trailing accessory stays independently tappable; pass `nil` while editing.
struct PlaylistRowCell: View {
    let thumbnailURL: URL?
    let videoId: String
    let thumbnailWidth: CGFloat
    let title: String
    let subtitle: String
    let isEditing: Bool
    var titleFont: Font = .subheadline.weight(.semibold)
    var subtitleFont: Font = .caption
    var onTap: (() -> Void)?
    var onRename: (() -> Void)?
    let onDelete: () -> Void
    /// Optional custom-reorder grip handling. When non-nil *and* editing, a leading
    /// grip (left of the thumbnail) is shown that reports its drag so the owning
    /// screen can perform a smooth reorder (the native handle is on the wrong side).
    var onGripChange: ((DragGesture.Value) -> Void)?
    var onGripEnded: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if isEditing, let onGripChange {
                leadingGrip(onGripChange)
            }
            leading
            Spacer(minLength: 0)
            PlaylistRowAccessory(isEditing: isEditing, onDelete: onDelete)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func leadingGrip(_ onGripChange: @escaping (DragGesture.Value) -> Void) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 32)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(onGripChange)
                    .onEnded { _ in onGripEnded?() }
            )
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
        if isEditing, let onRename {
            Button(action: onRename) {
                Text(title)
                    .font(titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .font(titleFont)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Top-level playlists screen: list of local playlists with an empty state,
/// swipe-to-delete, an edit mode (reorder handle, "×" per row, tappable-to-rename
/// name), and a "New" action that prompts for a name.
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
            .alert("Rename Playlist", isPresented: $model.showRenameAlert) {
                TextField("Name", text: $model.newName)
                Button("Save") {
                    model.commitRename(app: app)
                }
                Button("Cancel", role: .cancel) {
                    model.showRenameAlert = false
                }
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
            onTap: model.isEditing ? nil : { app.playlistsPath.append(playlist.id) },
            onRename: model.isEditing ? { model.beginRename(playlist) } : nil,
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
        guard refreshPlaylist(app: app) != nil else { return }
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
/// button, an ordered, reorderable list of its videos (reorder handle plus a
/// trailing "×"/chevron), and a menu of playlist actions.
struct PlaylistDetailScreen: View {
    @Environment(AppModel.self) private var app
    let playlistID: String
    @State private var model: PlaylistDetailModel
    @State private var dragItemID: String?
    @State private var dragOriginIndex = 0
    @State private var dragCurrentIndex = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var rowHeight: CGFloat = 79

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
        .toolbar { StandardToolbar() }
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
                        },
                        onGripChange: { value in handleGripDrag(item: item, value: value) },
                        onGripEnded: { handleGripDragEnd() }
                    )
                    .offset(y: dragItemID == item.stream.id ? dragTranslation - CGFloat(dragCurrentIndex - dragOriginIndex) * rowHeight : 0)
                    .zIndex(dragItemID == item.stream.id ? 1 : 0)
                    .scaleEffect(dragItemID == item.stream.id ? 1.05 : 1)
                    .shadow(color: .black.opacity(dragItemID == item.stream.id ? 0.18 : 0), radius: 8, x: 0, y: 4)
                    .opacity(dragItemID == item.stream.id ? 1 : (model.isEditing && dragItemID != nil ? 0.85 : 1))
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { rowHeight = $0 })
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
            }
        }
        .listStyle(.plain)
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
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
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

    private var playAllButton: some View {
        Button {
            Task { await model.playAll(app: app) }
        } label: {
            Label("Play", systemImage: "play.circle.fill")
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(model.isEditing || (playlist?.streams.isEmpty ?? true))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Custom reorder drag: tracks the touch, and when the accumulated translation
    /// has crossed a whole row height, moves the item in the manager from its current
    /// index to the target index (animated) so the other rows settle smoothly, then
    /// re-anchors so the drag translation doesn't accumulate (jitter-free).
    private func handleGripDrag(item: LocalPlaylistItem, value: DragGesture.Value) {
        guard let currentPlaylist = playlist else { return }
        let translation = value.translation.height
        if dragItemID != item.stream.id {
            let start = currentPlaylist.streams.firstIndex(where: { $0.stream.id == item.stream.id }) ?? 0
            dragItemID = item.stream.id
            dragOriginIndex = start
            dragCurrentIndex = start
            dragTranslation = translation
            return
        }
        dragTranslation = translation
        let count = currentPlaylist.streams.count
        let target = dragOriginIndex + Int((translation / rowHeight).rounded())
        let clamped = max(0, min(count - 1, target))
        guard clamped != dragCurrentIndex else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            app.playlists.moveItem(from: dragCurrentIndex, to: clamped, in: currentPlaylist)
            dragCurrentIndex = clamped
        }
    }

    /// Ends the reorder drag and lets the lifted row settle back to its final slot.
    private func handleGripDragEnd() {
        dragItemID = nil
        dragOriginIndex = 0
        dragCurrentIndex = 0
        dragTranslation = 0
    }

}
