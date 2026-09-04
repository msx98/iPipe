import SwiftUI
import AVKit
import UIKit

@Observable
@MainActor
final class VideoDetailModel {
    var stream: StreamItem?
    var related: [StreamItem] = []
    var formats: [VideoFormat] = []
    var isLoading = true
    var error: String?

    func load(app: AppModel, stream: StreamItem) async {
        isLoading = true
        error = nil
        do {
            let details = try await app.extraction.streamDetails(id: stream.id)
            self.stream = details.stream
            self.formats = details.formats
            self.related = details.related
            // If this video is already the active playback, don't restart it —
            // just refresh metadata/related so collapsing and re-expanding the
            // player keeps the related list populated.
            if app.player.currentStream?.id != stream.id || !app.player.hasItem {
                app.player.play(stream: details.stream, formats: details.formats, prefer: nil)
            }
            app.recordWatch(details.stream)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct VideoDetailView: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    @State private var model = VideoDetailModel()
    @State private var showDescription = false
    @State private var showAddToPlaylist = false
    @State private var isFullscreen = false
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let error = model.error {
                ErrorStateView(message: error) {
                    Task { await model.load(app: app, stream: stream) }
                }
            } else if model.isLoading {
                ProgressView("Loading…")
            } else {
                detailContent
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(app: app, stream: stream)
            if let watch = (model.stream ?? stream).watchURL {
                Log.url(watch.absoluteString)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(stream: model.stream ?? stream)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            FullscreenPlayerView(onExit: { isFullscreen = false })
        }
        .onChange(of: isFullscreen) { _, isFullscreen in
            setOrientation(isFullscreen ? .landscapeRight : .portrait)
        }
    }


    private var detailContent: some View {
        VStack(spacing: 0) {
            playerSection
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metadataSection
                    if !model.related.isEmpty {
                        Divider()
                        Text("Related").font(.headline)
                        LazyVStack(spacing: 14) {
                            ForEach(model.related) { related in
                                Button {
                                    app.focusedVideo = related
                                } label: {
                                    HStack(spacing: 10) {
                                        AsyncThumbnail(url: related.thumbnailURL, videoId: related.id)
                                            .frame(width: 140)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(related.title).font(.footnote.weight(.semibold)).lineLimit(2)
                                            Text(related.author).font(.caption2).foregroundStyle(.secondary)
                                            Text([related.viewCountText, related.publishedText].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
    }

    private var playerSection: some View {
        VStack(spacing: 8) {
            Group {
                if app.player.hasItem {
                    ZStack {
                        PlayerLayerRepresentable(view: app.player.playerLayerView)
                        if showControls {
                            PlayerControlsOverlay(
                                isFullscreen: isFullscreen,
                                onFullscreen: { isFullscreen = true }
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                } else {
                    ZStack {
                        Rectangle().fill(.black)
                        ProgressView().tint(.white)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())

            HStack {
                Menu {
                    ForEach(app.player.playbackOptions(model.formats)) { option in
                        Button {
                            app.player.play(stream: model.stream ?? stream, formats: model.formats, prefer: option.prefer)
                        } label: {
                            if option.label == app.player.currentLabel {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles.tv")
                        Text(app.player.currentLabel).lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .font(.footnote.weight(.medium))
                }
                Spacer()
            }
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        } else {
            controlsTask?.cancel()
        }
    }

    private func scheduleAutoHide() {
        controlsTask?.cancel()
        controlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if app.player.isPlaying {
                withAnimation(.easeOut(duration: 0.25)) { showControls = false }
            }
        }
    }

    @ViewBuilder
    private func downloadMenuItem(kind: DownloadKind) -> some View {
        let target = model.stream ?? stream
        if let item = app.downloads.item(for: target.id, kind: kind) {
            switch item.state {
            case .done:
                Button {
                } label: {
                    Label("Downloaded", systemImage: "checkmark")
                }
                .disabled(true)
            case .downloading:
                Button {
                } label: {
                    Text("Downloading… \(Int(item.progress * 100))%")
                }
                .disabled(true)
            case .failed:
                Button {
                    app.downloads.startDownload(stream: target, formats: model.formats, kind: kind)
                } label: {
                    Text("Retry download")
                }
            }
        } else {
            Button {
                app.downloads.startDownload(stream: target, formats: model.formats, kind: kind)
            } label: {
                Text(kind == .video ? "Download video" : "Download audio")
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.stream?.title ?? stream.title)
                .font(.title3.weight(.semibold))
            Text([model.stream?.viewCountText ?? stream.viewCountText, model.stream?.publishedText ?? stream.publishedText].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let authorId = model.stream?.authorId ?? stream.authorId {
                NavigationLink(value: ChannelItem(id: authorId, name: model.stream?.author ?? stream.author, handle: nil, avatarURL: nil, subscriberText: nil, descriptionText: "", videoCountText: nil)) {
                    HStack(spacing: 10) {
                        ChannelAvatar(name: model.stream?.author ?? stream.author, url: nil, size: 40)
                        Text(model.stream?.author ?? stream.author)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        app.player.togglePiP()
                    } label: {
                        Label("PiP", systemImage: "pip.enter")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        withAnimation { app.player.toggleBackground() }
                    } label: {
                        Label("Background", systemImage: "headphones")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack(spacing: 12) {
                    Menu {
                        downloadMenuItem(kind: .video)
                        downloadMenuItem(kind: .audio)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Label("Add to playlist", systemImage: "plus.circle")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let description = model.stream?.description, !description.isEmpty {
                Button {
                    showDescription.toggle()
                } label: {
                    Text(showDescription ? description : (description.isEmpty ? "No description" : String(description.prefix(120)) + (description.count > 120 ? "…" : "")))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Rotates the interface for fullscreen playback: landscape while the fullscreen
    /// player is presented, portrait on exit. Uses the modern scene-based geometry
    /// API plus a `UIDevice` nudge so both devices and simulators honor the request.
    private func setOrientation(_ orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let mask: UIInterfaceOrientationMask = orientation.isLandscape ? .landscape : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            NSLog("iPipe: orientation request failed: %@", error.localizedDescription)
        }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
    }

}

/// Hosts the shared `PlayerLayerView` owned by `PlayerModel`. Rendering through an
/// `AVPlayerLayer` (instead of SwiftUI's `VideoPlayer`) is what enables system
/// picture-in-picture: the layer backs an `AVPictureInPictureController` whose
/// lifecycle is managed by `PlayerModel`.
struct PlayerLayerRepresentable: UIViewRepresentable {
    let view: PlayerLayerView

    func makeUIView(context: Context) -> PlayerLayerView {
        view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        // The player is synced onto the layer by PlayerModel on playback changes.
    }
}

/// Playback controls overlaid on the video surface: a center play/pause button,
/// a seek slider with current/duration time labels, and a fullscreen toggle, all
/// over a subtle black scrim so they stay readable in light or dark mode.
/// Tapping anywhere on the video (outside a control) is handled by the container.
struct PlayerControlsOverlay: View {
    @Environment(AppModel.self) private var app
    let isFullscreen: Bool
    let onFullscreen: () -> Void
    /// Non-nil while the user is dragging the seek bar; the finger position is
    /// shown immediately and `seek(to:)` fires once on release.
    @State private var scrubTime: TimeInterval?

    /// True while background playback is active (audio continues in the background).
    /// Drives the inert headphone badge + the "x" exit button.
    private var isBackgroundMode: Bool {
        app.player.videoOutput == .background
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                if isBackgroundMode {
                    headphoneIndicator
                }
                Spacer()
                centerButtons
                Spacer()
                bottomBar
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            app.player.togglePlayPause()
        } label: {
            Image(systemName: app.player.playState ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.player.playState ? "Pause" : "Play")
    }

    /// Play/pause flanked by −10/+10 skip buttons (Netflix/YouTube layout).
    private var centerButtons: some View {
        HStack(spacing: 44) {
            skipBackwardButton
            playPauseButton
            skipForwardButton
        }
    }

    private var skipBackwardButton: some View {
        Button {
            app.player.skipBackward()
        } label: {
            Image(systemName: "gobackward.10")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back 10 seconds")
    }

    private var skipForwardButton: some View {
        Button {
            app.player.skipForward()
        } label: {
            Image(systemName: "goforward.10")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Forward 10 seconds")
    }

    /// The slider range is always at least 1 so `0...1` stays valid before a
    /// duration is known. `displayCurrentTime` drives both the thumb and the time
    /// label so scrubbing feels instant while dragging.
    private var displayCurrentTime: TimeInterval {
        scrubTime ?? min(app.player.currentTime, app.player.currentDuration)
    }

    /// Inert gray headphone badge shown at the top-right while background mode is
    /// active; purely visual, no action.
    private var headphoneIndicator: some View {
        HStack {
            Spacer()
            Image(systemName: "headphones")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.gray)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .accessibilityLabel("Background mode active")
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text(displayCurrentTime.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 44, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { displayCurrentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(app.player.currentDuration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubTime = min(app.player.currentTime, app.player.currentDuration)
                    } else if let scrub = scrubTime {
                        app.player.seek(to: scrub)
                        scrubTime = nil
                    }
                }
            )
            .tint(.white)
            Text(app.player.currentDuration.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 44, alignment: .leading)
            if isBackgroundMode {
                Button {
                    withAnimation { app.player.toggleBackground() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit background mode")
            } else {
                Button {
                    onFullscreen()
                } label: {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFullscreen ? "Exit fullscreen" : "Fullscreen")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

/// Full-screen presentation of the player (black background, hidden system UI).
/// Uses its own `PlayerLayerView` so it can coexist with the inline surface
/// (a `UIView` can only live in one place at a time) while still showing the
/// shared `AVPlayer`. Controls mirror the inline overlay; the fullscreen button
/// becomes an "exit" button.
struct FullscreenPlayerView: View {
    @Environment(AppModel.self) private var app
    let onExit: () -> Void
    @State private var layerView = PlayerLayerView()
    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            PlayerLayerRepresentable(view: layerView)
                .onAppear { syncPlayer() }
            if showControls {
                PlayerControlsOverlay(
                    isFullscreen: true,
                    onFullscreen: { onExit() }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    private func syncPlayer() {
        layerView.playerLayer.player = app.player.player
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        } else {
            controlsTask?.cancel()
        }
    }

    private func scheduleAutoHide() {
        controlsTask?.cancel()
        controlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if app.player.isPlaying {
                withAnimation(.easeOut(duration: 0.25)) { showControls = false }
            }
        }
    }
}
