# AGENTS.md

## Project

**iPipe** — a Swift/SwiftUI port of the NewPipe YouTube client. Pure-Swift, no CocoaPods/SPM deps, iOS 18+, Swift 5. Single app target, no test target.

## Layout

```
iPipe/                    # iOS Swift source (the app)
iPipe.xcodeproj/          # Single-target Xcode project
Makefile                  # build / install / launch pipeline
```

## iOS app

### Entry points
- `iPipe/iPipeApp.swift` — `@main` SwiftUI `App`. Creates `AppModel`, injects via `.environment`, applies color scheme.
- `iPipe/ContentView.swift` — Root 4-tab `TabView` (Trending, Search, Subscriptions, Settings) + `MiniPlayerBar` via `.safeAreaInset`.

### `Core/`
- `AppModel.swift` — `@Observable @MainActor` central state: `backend`, `player`, `downloads`, `signedIn`, `subscriptions`, `history`, `colorSchemeChoice`. Persists to `UserDefaults`. On init, ingests `Documents/cookies.txt` via `CookieStore`.
- `Models/Models.swift` — `StreamItem`, `ChannelItem`, `PlaylistItem`, `CommentItem`, `VideoFormat` (hls/muxed/videoOnly/audioOnly), `SearchResultKind`, `ExtractionError`, `SearchFilter`.
- `Extraction/ExtractionService.swift` — Protocol: `trending`, `search`, `suggestions`, `streamDetails`, `channel`, `resolveChannelID`.
- `Extraction/InnerTubeClient.swift` — Real YouTube extraction via `youtubei/v1/{browse,search,player,next}`. Uses iOS, WEB, ANDROID client fingerprints (ANDROID recovers extra formats). Reads cookies, signs requests with SAPISIDHASH when signed in. Contains JSON tree walker + renderer parsers.
- `Extraction/MockExtractionService.swift` — In-memory sample data (Big Buck Bunny etc.) for offline/dev.
- `Services/CookieStore.swift` — Thread-safe singleton. Keychain group `<TEAM_ID>.ax.lx.ipipe` (`TEAM_ID` read from Info.plist at runtime, fallback `A1111ABCDE`). Parses Netscape .txt + JSON. `ingestDroppedFile()` reads `Documents/cookies.txt` and deletes it.
- `Services/DownloadManager.swift` — `@Observable @MainActor`. URLSession-based. Picks best video (≤1080p) + audio (itag 140), per-part progress, persists `DownloadItem`s to `UserDefaults`, files under `Documents/Downloads/`.
- `Player/PlayerModel.swift` — AVPlayer wrapper. Builds synthetic HLS manifests on the fly (`HLSResourceLoader`, `HLSBuilder`) so video-only/audio-only streams play. Registers `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`. `playDownload(...)` composes local files via `AVMutableComposition`.
- `Theme/Theme.swift` — Accent color + color-scheme picker mapping + `durationText` extension on `TimeInterval`.

### `Shared/Components/`
Reusable SwiftUI views: `StreamCard`, `ChannelRow`, `ChannelAvatar`, `AsyncThumbnail`, `ErrorStateView`, `LoadingFooter`.

### `Features/` (one screen per folder, each with paired `@Observable` view model)
- `Trending/TrendingView.swift` — Trending feed; refreshable; toolbar opens `DownloadsView` as a sheet.
- `Search/SearchView.swift` — `.searchable` + filter chips (All/Videos/Channels/Playlists) + suggestions.
- `Subscriptions/SubscriptionsView.swift` — Subscribed channels list, swipe-to-delete.
- `VideoDetail/VideoDetailView.swift` — Main player screen. `AVKit.VideoPlayer`, metadata + description + related. Toolbar Menu: Download video / Download audio. Quality picker.
- `Channel/ChannelView.swift` — Resolves handle → channel ID, header + video list.
- `Settings/SettingsView.swift` — Backend picker (InnerTube vs Sample), Theme picker, Clear history, Account (sign in/out, export/import cookies), About.
- `Settings/YouTubeLoginView.swift` — `WKWebView` login, pulls cookies via `WKWebsiteDataStore` into `CookieStore`.
- `Downloads/DownloadsView.swift` — `DownloadManager.items` list, swipe-to-delete.

### Info
- `Assets.xcassets/` — `AppIcon`, `AccentColor`.

## Build / install / launch (Makefile)

`make help` lists targets. The common pipeline is `make build` → `make install`.

| Target | What it does |
|---|---|
| `make help` | List targets from `##` comments |
| `make build` | `xcodebuild` Release, unsigned, stages to `build/app/<ARCH>/`. Smart-skips if git tree clean and `BUNDLE_ID` unchanged. |
| `make install` | Device: build + `devicectl install` (unsigned). Simulator: build + `simctl install`. Optional `COOKIESFILE=<path>` drops cookies into `Documents/`. |
| `make clean` | `rm -rf build/` |

Key vars: `ARCH` (default `device`, use `simulator` for sim work), `BUNDLE_ID` (default `ax.lx.ipipe`), `DEVICE` (default `iPhone` or `$UDID_IPHONE`), `TEAM_ID` (default `A1111ABCDE`, feeds Info.plist key + `DEVELOPMENT_TEAM`), `COOKIESFILE`.

## Conventions / gotchas

- View models are `@Observable @MainActor final class XxxModel` (iOS 17 Observation framework).
- `AppModel`, `PlayerModel`, `DownloadManager`, `CookieStore` are all `@MainActor`/`@Observable`.
- Backend is interchangeable: `InnerTubeClient` (real YouTube) vs `MockExtractionService` (sample). Switch in Settings.
- Only system frameworks: SwiftUI, AVFoundation, AVKit, MediaPlayer, WebKit, Security, Observation.
- `NSLog("iPipe: ...")` is used for cookie-ingest logging.

## Debugging on the simulator

Bundle ID is **`ax.lx.ipipe`**. Use the `mcp__ios-simulator__*` tools for any simulator interaction. **Don't be afraid to use screenshots** — they show what the user actually sees and are cheap. Use the accessibility tools when you need to find/inspect a specific element; reach for a screenshot to confirm the overall look or to read text/content that isn't exposed to accessibility.

- `ios-simulator_screenshot` — first stop for "what does this look like right now?".
- `ios-simulator_ui_describe_all` — full accessibility tree when you need structure.
- `ios-simulator_ui_find_element` — search by label/id (e.g. find a tab, button, or cell).
- `ios-simulator_ui_describe_point` — element at a coordinate.
- `ios-simulator_ui_tap`, `ios-simulator_ui_swipe`, `ios-simulator_ui_type` — interact.
- `ios-simulator_launch_app` (pass `terminate_running: true` to relaunch) / `ios-simulator_terminate_app` with `bundleId: "ax.lx.ipipe"`.
- `ios-simulator_log_process` — stream the app's logs; the launch tool returns a log file path you can also tail.

**Batch actions in a single turn whenever they don't depend on each other** — taps, swipes, types, screenshots, and log reads can all be issued in parallel. Don't wait one step at a time if the next step doesn't need the previous result.

### Typical inner loop
1. Edit Swift code.
2. `make ARCH=simulator install` (rebuilds only if needed).
3. `ios-simulator_launch_app` with `bundleId: "ax.lx.ipipe"`, `terminate_running: true`.
4. `ios-simulator_ui_describe_all` / `ios-simulator_ui_find_element` to inspect (or `ios-simulator_screenshot` for visual issues).
5. `ios-simulator_ui_tap` / `ios-simulator_ui_swipe` / `ios-simulator_ui_type` to interact.
6. Tail the launch log file to see what the app is doing.

### Pushing cookies (for signed-in flows)
```
make ARCH=simulator install COOKIESFILE=./cookies.txt
```
On next launch, `AppModel.init()` → `CookieStore.ingestDroppedFile()` imports and deletes the file.
