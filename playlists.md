# Local Playlists — iPipe feature spec

Goal: add **local playlists** support to iPipe, porting the NewPipe "local playlist" feature.
Reference implementation lives in the sibling repo (read these files, don't rewrite them in
Java/Kotlin — adapt the *behaviour* to iPipe's Swift/SwiftUI + UserDefaults architecture):

```
~/Repositories/NewPipe-iOS/Android/app/src/main/java/org/schabi/newpipe/local/playlist/
    LocalPlaylistManager.java      create/append/update/rename/thumbnail/remove/dups/watched
    RemotePlaylistManager.kt       (remote/bookmarked playlists — OUT OF SCOPE unless easy)
    LocalPlaylistViewModel.kt      removeWatched / removeDuplicates work states
    ExportPlaylist.kt / PlayListShareMode.kt   share/export
    LocalPlaylistFragment.java     UI: header(list of playlists) + per-playlist stream list,
                                   drag-to-reorder, rename dialog, share dialog, context menu
~/Repositories/NewPipe-iOS/Android/app/src/main/java/org/schabi/newpipe/database/playlist/
    model/PlaylistEntity.kt        name, thumbnailStreamId, thumbnailPermanent, displayIndex
    PlaylistStreamEntry.kt         stream + join index
    PlaylistMetadataEntry.kt       streamCount, thumbnailUrl
```

## What "local playlist" means in NewPipe (what we are porting)
- A user-curated, **locally stored** ordered list of videos (a queue/bookmark list).
- **Create** a playlist from one or more videos (new playlists land on top, negative displayIndex).
- **Append** existing videos to an existing playlist.
- **View** a playlist: header (name, stream count + total duration) + ordered stream list.
- **Edit**: rename, delete, drag-to-reorder, remove an item (thumbnail auto-updates).
- **Remove duplicates** (keep first occurrence).
- **Remove watched** videos (uses history) — optionally partially watched.
- **Play all** as a sequential queue; tap a single item to open its detail page.
- **Share / export**: (1) just URLs, (2) URLs with titles, (3) YouTube temporary playlist
  (`https://www.youtube.com/watch_videos?video_ids=id1,id2,...`, capped at 50, reversed order).

## iPipe-specific design decisions
- iPipe has **no Room database / stream table**. Persist as JSON arrays in `UserDefaults`,
  exactly like `AppModel.history`, `AppModel.subscriptions`, and `DownloadManager.items`.
- Embed the full `StreamItem` inside each playlist item (no separate dedup stream table).
  Dedup / reorder / remove operate on the embedded items by `StreamItem.id`.
- NewPipe exposes local playlists as a first-class navigation tab; add a 5th bottom tab
  **Playlists** (`"list.bullet"`) to mirror that. Wire it in `ContentView`.
- Existing `PlaylistItem` in `Core/Models/Models.swift` is a *remote/search* playlist — do
  NOT reuse the name. New types live in `Core/Models/PlaylistModels.swift`.

### Data models (`Core/Models/PlaylistModels.swift`)
```swift
struct LocalPlaylistItem: Identifiable, Codable, Hashable {
    var id: String        // UUID, unique per item within a playlist
    var stream: StreamItem
}

struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id: String        // UUID, unique per playlist
    var name: String
    var thumbnailStreamID: String?   // explicit thumbnail; nil == auto (first stream)
    var streams: [LocalPlaylistItem]
}

enum PlaylistShareMode: String, CaseIterable, Identifiable {
    case justUrls, withTitles, youtubeTemp
    var id: String { rawValue }
}

/// A queue element the player needs to actually play. Built from a playlist when "Play all" runs.
struct QueueItem: Hashable {
    var stream: StreamItem
    var formats: [VideoFormat]
    var prefer: VideoFormat?
}
```

### Manager (`Core/Services/LocalPlaylistManager.swift`)
`@Observable @MainActor final class LocalPlaylistManager`. Mirror `DownloadManager`'s
load()/save() pattern (`private static let storageKey = "np.playlists.v1"`,
`UserDefaults.standard`). Expose `var playlists: [LocalPlaylist] = []`.

Methods:
- `func create(_ name: String, streams: [StreamItem]) -> LocalPlaylist?` — reject empty;
  new playlist on top (prepend); thumbnail = first stream id.
- `func append(_ streams: [StreamItem], to playlist: LocalPlaylist) -> Bool` — skip streams
  already present (dedup by `stream.id`); returns whether anything changed.
- `func delete(_ playlist: LocalPlaylist)`
- `func rename(_ playlist: LocalPlaylist, to name: String)`
- `func moveItem(from offsets: IndexSet, to destination: Int)` and
  `func moveItem(_ item: LocalPlaylistItem, within playlist: LocalPlaylist)` (for `.onMove`)
- `func removeItem(_ item: LocalPlaylistItem, from playlist: LocalPlaylist)` — update thumbnail
  if the removed item was the thumbnail.
- `func removeDuplicates(from playlist: LocalPlaylist)` — keep first occurrence of each id.
- `func removeWatched(in playlist: LocalPlaylist, watchedIDs: Set<String>)` — remove items
  whose `stream.id` is in `watchedIDs`. (iPipe history only records *that* a video was watched,
  not progress, so this removes fully-watched videos only — no "partial watch" option.)
- `func export(_ playlist: LocalPlaylist, mode: PlaylistShareMode) -> String` —
  `withTitles`: `"title\nurl"` per line; `justUrls`: url per line;
  `youtubeTemp`: reversed ids (cap 50) joined with commas into
  `https://www.youtube.com/watch_videos?video_ids=…`.
- private `save()`, `load()`; `load()` runs in `init()`.

### AppModel integration (`Core/AppModel.swift`)
Add `let playlists = LocalPlaylistManager()` alongside `player` / `downloads`. It is already
loaded in `init()` via the manager's own `load()`.

### Player queue (`Core/Player/PlayerModel.swift`)
Add sequential-queue playback (single-stream `play(...)` stays unchanged):
- `var queue: [QueueItem] = []; var queueIndex = 0; private var endObserver: NSKeyValueObservation?`
- `func playQueue(_ items: [QueueItem], startAt: Int = 0)` — clears any existing end observer,
  sets the queue, and plays the start item via the existing `play(...)`.
- `func playNext()` / internal `onItemEnded()` — on `AVPlayerItem` end-of-stream, advance
  `queueIndex` and play the next; when the queue is exhausted, stop/clear (leave the last
  frame, reset `queue`).
- Register the end trigger on the current `AVPlayerItem` in `playNext` (observe `.status ==
  .ended`, and/or `AVPlayerItem.didPlayToEndTimeNotification`). Re-register each time the item
  changes so the observer always targets the active item.
- `currentStream`/`currentTitle`/`currentAuthor` keep updating as the queue advances (the
  mini-player follows automatically).

### UI (`Features/Playlists/PlaylistsView.swift`)
Two screens behind a `NavigationStack(path:)`:

1. **PlaylistsListScreen** (`@Observable PlaylistsListModel`):
   - Lists `app.playlists.playlists` (name + stream count + total duration + thumbnail).
     Empty state via `ContentUnavailableView("No playlists yet", …)`.
   - `.swipeToDelete` on each playlist.
   - Tapping a playlist pushes the detail screen.
   - Toolbar "New" → prompts for a name, creates an empty playlist, then pushes it (or guard:
     New creates a playlist you then populate from a video). Simpler: New creates a named empty
     playlist and opens it; the user appends videos from the video detail page.
2. **PlaylistDetailScreen** (`@Observable PlaylistDetailModel`, holds the `LocalPlaylist`):
   - Header: name (tap to rename via `.alert` with a `TextField`), stream count + total
     duration; if empty, show `ContentUnavailableView`.
   - Ordered list of `LocalPlaylistItem` rows (`AsyncThumbnail` + title + author).
     `.onMove` to reorder, `.onDelete` to remove.
   - Toolbar: **Play all** (`▶`), **Rename**, **Remove duplicates** (⧉), **Remove watched**
     (🕑, only if some items are in `app.history`), **Share** (⤳), **Delete**.
   - Tapping a row pushes that video's `VideoDetailView(stream:)` (consistent with the rest of
     the app).
   - "Play all" builds `QueueItem`s by fetching `streamDetails` for each playlist item
     (parallel via `TaskGroup`, cap ~100; skip failures) then calls
     `app.player.playQueue(queue)`. If a fetch fails, that item is skipped.

### "Add to playlist" entry point (`Features/VideoDetail/VideoDetailView.swift`)
Add a menu item (next to the existing Download menu, e.g. in the trailing toolbar or the
player-quality menu) **"Add to playlist"** that presents a sheet/alert listing the user's
playlists + **"New playlist…"**. Selecting an existing playlist appends the current video;
"New playlist…" creates one (name prompt) with the current video. After the change, refresh
`app.playlists.playlists` (it's `@Observable`, so the list screen auto-updates). Guard: don't
re-add a video already in the selected playlist.

## Conventions to follow (see AGENTS.md)
- View models / managers: `@Observable @MainActor final class XxxModel` / `XxxManager`.
- Persistence via `UserDefaults` + `JSONEncoder/Decoder`, `.v1` suffix keys.
- System frameworks only (SwiftUI, Observation, AVFoundation, AVKit, UniformTypeIdentifiers).
- Use `Log.swift` for NSLog if needed. Match existing styling (RoundedRectangle 10, Theme.accent).

## Verify
1. `make ARCH=simulator build` — must compile. Fix any errors; do not commit.
2. `make ARCH=simulator install` then `ios-simulator_launch_app` `bundleId: ax.lx.ipipe`
   (`terminate_running: true`).
3. Smoke test: Trending → open a video → **Add to playlist** → create "My List" → open the
   **Playlists** tab → tap it → **Play all** (queue advances between videos) → **Remove
   duplicates** / **Remove watched** / **Rename** / drag to reorder / **Share**.
4. Tail the launch log / `ios-simulator_screenshot` to confirm no crashes and correct state.

## Out of scope (unless trivially easy)
- Remote/bookmarked online playlists (`RemotePlaylistManager`).
- "Set as thumbnail" per-item (auto thumbnail = first stream is enough).
- Partially-watched removal (iPipe history has no per-video progress).
