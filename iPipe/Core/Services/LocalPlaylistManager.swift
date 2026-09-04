import Foundation
import Observation

@Observable
@MainActor
final class LocalPlaylistManager {
    var playlists: [LocalPlaylist] = []

    private static let storageKey = "np.playlists.v1"

    init() {
        load()
    }

    @discardableResult
    func create(_ name: String, streams: [StreamItem]) -> LocalPlaylist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = LocalPlaylist(
            id: UUID().uuidString,
            name: trimmed,
            thumbnailStreamID: streams.first?.id,
            streams: streams.map { LocalPlaylistItem(id: UUID().uuidString, stream: $0) }
        )
        playlists.insert(playlist, at: 0)
        save()
        return playlist
    }

    @discardableResult
    func append(_ streams: [StreamItem], to playlist: LocalPlaylist) -> Bool {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return false }
        var changed = false
        for stream in streams where !playlists[idx].streams.contains(where: { $0.stream.id == stream.id }) {
            playlists[idx].streams.append(LocalPlaylistItem(id: UUID().uuidString, stream: stream))
            changed = true
        }
        if changed { save() }
        return changed
    }

    func delete(_ playlist: LocalPlaylist) {
        let idx = playlists.firstIndex(where: { $0.id == playlist.id })
        guard let idx else { return }
        playlists.remove(at: idx)
        save()
    }

    func rename(_ playlist: LocalPlaylist, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }),
              !name.isEmpty else { return }
        playlists[idx].name = name
        save()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        playlists.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func moveItem(from offsets: IndexSet, to destination: Int, in playlist: LocalPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].streams.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func moveItem(_ item: LocalPlaylistItem, within playlist: LocalPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard let index = playlists[idx].streams.firstIndex(where: { $0.stream.id == item.stream.id }) else { return }
        let element = playlists[idx].streams.remove(at: index)
        playlists[idx].streams.append(element)
        save()
    }

    /// Moves the item at `fromIndex` to `toIndex` (indices reflect the playlist's
    /// current stream order) and persists the result. Used by the custom
    /// drag-to-reorder grip since the native reorder control cannot be relocated.
    func moveItem(from fromIndex: Int, to toIndex: Int, in playlist: LocalPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let count = playlists[idx].streams.count
        guard fromIndex >= 0, fromIndex < count, toIndex >= 0, toIndex < count, fromIndex != toIndex else { return }
        let element = playlists[idx].streams.remove(at: fromIndex)
        playlists[idx].streams.insert(element, at: toIndex)
        save()
    }

    func removeItem(_ item: LocalPlaylistItem, from playlist: LocalPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].streams.removeAll { $0.stream.id == item.stream.id }
        fixThumbnail(at: idx)
        save()
    }

    func removeDuplicates(from playlist: LocalPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var seen = Set<String>()
        var kept = [LocalPlaylistItem]()
        for item in playlists[idx].streams where seen.insert(item.stream.id).inserted {
            kept.append(item)
        }
        playlists[idx].streams = kept
        fixThumbnail(at: idx)
        save()
    }

    func removeWatched(in playlist: LocalPlaylist, watchedIDs: Set<String>) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[idx].streams.removeAll { watchedIDs.contains($0.stream.id) }
        fixThumbnail(at: idx)
        save()
    }

    func export(_ playlist: LocalPlaylist, mode: PlaylistShareMode) -> String {
        let items = playlist.streams
        switch mode {
        case .withTitles:
            return items.map { "\($0.stream.title)\n\($0.stream.watchURL?.absoluteString ?? "https://www.youtube.com/watch?v=\($0.stream.id)")" }.joined(separator: "\n")
        case .justUrls:
            return items.map { $0.stream.watchURL?.absoluteString ?? "https://www.youtube.com/watch?v=\($0.stream.id)" }.joined(separator: "\n")
        case .youtubeTemp:
            let ids = items
                .compactMap { Self.youtubeID(from: $0.stream.watchURL) }
                .reversed()
                .prefix(50)
            return "https://www.youtube.com/watch_videos?video_ids=" + ids.joined(separator: ",")
        }
    }

    private func fixThumbnail(at idx: Int) {
        var tid = playlists[idx].thumbnailStreamID
        if let current = tid {
            if !playlists[idx].streams.contains(where: { $0.stream.id == current }) {
                tid = playlists[idx].streams.first?.id
            }
        } else {
            tid = playlists[idx].streams.first?.id
        }
        playlists[idx].thumbnailStreamID = tid
    }

    private static func youtubeID(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "v" })?.value
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([LocalPlaylist].self, from: data) {
            playlists = decoded
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
