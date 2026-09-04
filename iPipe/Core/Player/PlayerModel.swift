import AVFoundation
import AVKit
import MediaPlayer
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class PlayerModel {
    /// Where the on-screen video is currently "output": `.normal` (rendered in
    /// the app), `.background` (audio keeps playing while the app is backgrounded),
    /// or `.pip` (system picture-in-picture). Drives the play-state tuple.
    enum VideoOutput {
        case normal, background, pip
    }

    var player: AVPlayer?
    var currentTitle = ""
    var currentAuthor = ""
    var currentLabel = ""
    var isPlaying = false
    var currentStream: StreamItem?
    var hasItem: Bool { player != nil }

    /// Whether the user intends the current video to be playing. This intent
    /// survives app backgrounding (it is never cleared by a scene-phase change),
    /// so returning to the foreground restores whatever mode playback was in.
    var playWhenForegrounded = false
    /// Where the video is currently output (`normal` / `background` / `pip`).
    var videoOutput: VideoOutput = .normal
    /// Whether the app is currently foregrounded (scene phase `.active`).
    var appForegrounded = true

    /// The effective play/pause state: the `AVPlayer` plays exactly when this is
    /// true and pauses otherwise. Playback keeps running while backgrounded or in
    /// PiP even if `appForegrounded` is false.
    var playState: Bool {
        playWhenForegrounded && (appForegrounded || videoOutput == .background || videoOutput == .pip)
    }

    /// UIKit host for the inline video surface. Rendering through an `AVPlayerLayer`
    /// (rather than SwiftUI's `VideoPlayer`) is what lets us drive real system
    /// picture-in-picture: it backs an `AVPictureInPictureController` and is held
    /// here on the model so PiP survives navigation / backgrounding.
    let playerLayerView = PlayerLayerView()
    private let pipController: AVPictureInPictureController?
    private let pipDelegate = PlayerPiPDelegate()
    var isPiPActive = false

    /// Toggles between `.normal` (in-app) and `.background` (audio keeps playing
    /// while the app is backgrounded). Entering a background output keeps the
    /// shared `AVAudioSession` active (`.playback` category, alongside
    /// `UIBackgroundModes` = `audio`) so audio continues in the background; leaving
    /// every background output deactivates it so app backgrounding pauses again.
    func toggleBackground() {
        if videoOutput == .background {
            videoOutput = .normal
            deactivateBackgroundAudio()
        } else {
            videoOutput = .background
            activateBackgroundAudio()
        }
        syncPlayState()
    }

    /// Sets the video output directly — used by system picture-in-picture: `.pip`
    /// when PiP starts, `.normal` when it stops. PiP keeps the audio session active
    /// so playback continues offscreen.
    func setVideoOutput(_ output: VideoOutput) {
        videoOutput = output
        if videoOutput == .pip || videoOutput == .background {
            activateBackgroundAudio()
        } else {
            deactivateBackgroundAudio()
        }
        syncPlayState()
    }

    /// Scene lifecycle. `true` when the app is active (foreground), `false` when
    /// backgrounded. Pausing/restoring is delegated to `syncPlayState()`, which
    /// keeps playing while a background or PiP output is active.
    func updateAppForegrounded(_ isActive: Bool) {
        appForegrounded = isActive
        syncPlayState()
    }

    /// Reconciles the real `AVPlayer` play/pause state with `playState`, keeping
    /// `isPlaying` and the Now Playing info in sync. Called whenever any of the
    /// play-state tuple (`playWhenForegrounded` / `videoOutput` / `appForegrounded`)
    /// changes.
    private func syncPlayState() {
        guard let player else {
            isPlaying = false
            return
        }
        if playState {
            if player.timeControlStatus != .playing {
                player.play()
            }
            isPlaying = true
        } else {
            if player.timeControlStatus == .playing || player.rate != 0 {
                player.pause()
            }
            isPlaying = false
        }
        updateNowPlaying()
    }

    private func activateBackgroundAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func deactivateBackgroundAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    init() {
        pipController = AVPictureInPictureController(playerLayer: playerLayerView.playerLayer)
        pipController?.delegate = pipDelegate
        pipDelegate.onStateChange = { [weak self] active in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPiPActive = active
                self.setVideoOutput(active ? .pip : .normal)
            }
        }
    }

    /// Toggles system picture-in-picture: starts it when idle, stops it when active.
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    func startPiP() {
        guard player != nil else { return }
        guard let pip = pipController else {
            NSLog("iPipe: PiP controller is nil")
            return
        }
        NSLog("iPipe: PiP controller exists, pipPossible=%d pipActive=%d", pip.isPictureInPicturePossible ? 1 : 0, pip.isPictureInPictureActive ? 1 : 0)
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else {
            NSLog("iPipe: PiP not possible yet")
        }
    }

    func stopPiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
    }

    var queue: [QueueItem] = []
    var queueIndex = 0
    var queueFinished = false
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    var currentTime: TimeInterval = 0

    var currentDuration: TimeInterval { max(duration, 1) }

    func playQueue(_ items: [QueueItem], startAt: Int = 0) {
        guard !items.isEmpty else { return }
        queueFinished = false
        removeEndObserver()
        queue = items
        queueIndex = max(0, min(startAt, items.count - 1))
        let first = queue[queueIndex]
        play(stream: first.stream, formats: first.formats, prefer: first.prefer)
        registerEndObserver()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        if queueIndex + 1 < queue.count {
            queueFinished = false
            queueIndex += 1
            let next = queue[queueIndex]
            play(stream: next.stream, formats: next.formats, prefer: next.prefer)
            registerEndObserver()
        } else {
            finishQueue()
        }
    }

    /// Called when the last item finishes: keep the queue intact so it can be
    /// restarted, but stop playback and mark the queue as finished. Resets the
    /// play-state tuple to the default (paused, normal output).
    private func finishQueue() {
        queueFinished = true
        playWhenForegrounded = false
        videoOutput = .normal
        deactivateBackgroundAudio()
        currentTime = duration
        removeEndObserver()
        syncPlayState()
    }

    func onItemEnded() {
        playNext()
    }

    /// Restarts the queue from the first item (used from the finished state).
    func restartQueue() {
        guard !queue.isEmpty else { return }
        queueFinished = false
        playQueue(queue, startAt: 0)
    }

    /// Empties the queue and stops playback entirely.
    func clearQueue() {
        queueFinished = false
        queue = []
        queueIndex = 0
        stop()
    }

    /// Moves queue items (drag-to-reorder), keeping the active index tracking
    /// whichever stream was playing.
    func moveQueueItem(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard offsets.first != nil else { return }
        let activeID = queueIndex < queue.count ? queue[queueIndex].stream.id : nil
        queue.move(fromOffsets: offsets, toOffset: destination)
        if let id = activeID, let newIndex = queue.firstIndex(where: { $0.stream.id == id }) {
            queueIndex = newIndex
        }
    }

    func seek(to time: TimeInterval) {
        let seconds = max(0, time)
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero,
                     toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlaying()
    }

    func skipForward() {
        seek(to: currentTime + 10)
    }

    func skipBackward() {
        seek(to: currentTime - 10)
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if queueIndex > 0 {
            playFromQueue(at: queueIndex - 1)
        } else {
            seek(to: 0)
        }
    }

    private func startTimeObserver() {
        stopTimeObserver()
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
                self?.updateNowPlaying()
            }
        }
    }

    private func stopTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func registerEndObserver() {
        removeEndObserver()
        guard let item = player?.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onItemEnded()
            }
        }
    }

    struct PlaybackOption: Identifiable {
        let id: String
        let label: String
        let prefer: VideoFormat?
    }

    private var duration: TimeInterval = 0
    private var commandsRegistered = false

    func playbackOptions(_ formats: [VideoFormat]) -> [PlaybackOption] {
        var options: [PlaybackOption] = []
        let videos = formats
            .filter { $0.kind == .videoOnly && $0.label.contains("mp4") }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        options.append(contentsOf: videos.map { PlaybackOption(id: $0.id, label: "\($0.height ?? 0)p · video + audio", prefer: $0) })
        let muxed = formats
            .filter { $0.kind == .muxed }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        options.append(contentsOf: muxed.map { PlaybackOption(id: $0.id, label: "\($0.height ?? 360)p · muxed", prefer: $0) })
        let audio = formats.filter { $0.kind == .audioOnly }
        options.append(contentsOf: audio.map { PlaybackOption(id: $0.id, label: "Audio only", prefer: $0) })
        return options
    }

    func play(stream: StreamItem, formats: [VideoFormat], prefer: VideoFormat?) {
        setupAudioSession()
        registerRemoteCommands()
        queueFinished = false
        // Keep the latent queue consistent: a brand-new video collapses the queue
        // to just that video; re-selecting the current one (e.g. quality change)
        // updates its entry in place without disturbing the rest of the queue.
        if queue.isEmpty || queueIndex >= queue.count || queue[queueIndex].stream.id != stream.id {
            queue = [QueueItem(stream: stream, formats: formats, prefer: prefer)]
            queueIndex = 0
        } else {
            queue[queueIndex].formats = formats
            queue[queueIndex].prefer = prefer
        }
        currentTitle = stream.title
        currentAuthor = stream.author
        currentStream = stream
        duration = stream.duration ?? 0
        guard let chosen = prefer ?? defaultFormat(from: formats) else {
            NSLog("iPipe: no playable format for %@", stream.id)
            return;
        }
        // All formats are progressive files (mp4/webm), not HLS streams.
        // Synthesized HLS playlists pointing at those files never loaded
        // (raw mp4 is not a valid MPEG-TS segment) and showed a black screen.
        let item = AVPlayerItem(url: chosen.url)
        playWhenForegrounded = true
        setOrReplaceItem(item)
        currentLabel = chosen.label
        nowPlayingArtwork = nil
        if stream.thumbnailURL != nil {
            Task { await loadArtwork(for: stream) }
        }
        NSLog("iPipe: playing %@ via %@ (%@)", stream.id, chosen.kind.rawValue, chosen.label)
    }

    func togglePlayPause() {
        guard player != nil else { return }
        playWhenForegrounded.toggle()
        syncPlayState()
    }

    func stop() {
        removeEndObserver()
        stopTimeObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerLayerView.playerLayer.player = nil
        currentStream = nil
        playWhenForegrounded = false
        videoOutput = .normal
        deactivateBackgroundAudio()
        isPlaying = false
        currentTime = 0
        queue = []
        queueIndex = 0
        queueFinished = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Jumps the queue to the given index and plays that item (re-registering the
    /// end-of-stream trigger so the rest of the queue keeps advancing).
    func playFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queueFinished = false
        queueIndex = index
        let item = queue[index]
        play(stream: item.stream, formats: item.formats, prefer: item.prefer)
        registerEndObserver()
    }

    /// Removes an item from the queue. If it was the active video, playback moves
    /// to the next item, or stops entirely when the queue becomes empty.
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let wasActive = index == queueIndex
        removeEndObserver()
        if index < queueIndex { queueIndex -= 1 }
        queue.remove(at: index)
        if wasActive {
            if !queue.isEmpty {
                queueIndex = min(index, queue.count - 1)
                let item = queue[queueIndex]
                play(stream: item.stream, formats: item.formats, prefer: item.prefer)
                registerEndObserver()
            } else {
                queue = []
                queueIndex = 0
                stop()
            }
        }
    }

    func reactivateAudioSession() {
        setupAudioSession()
        syncPlayState()
    }

    func playDownload(video: URL?, audio: URL?, title: String, author: String, duration: TimeInterval) async {
        setupAudioSession()
        registerRemoteCommands()
        currentTitle = title
        currentAuthor = author
        self.duration = duration
        currentLabel = "Download"
        var item: AVPlayerItem?
        if let video, let audio {
            item = await localCompositionItem(video: video, audio: audio, fallbackDuration: duration) ?? AVPlayerItem(url: video)
        } else if let video {
            item = AVPlayerItem(url: video)
        } else if let audio {
            item = AVPlayerItem(url: audio)
        }
        guard let item else { return }
        playWhenForegrounded = true
        setOrReplaceItem(item)
    }

    private func defaultFormat(from formats: [VideoFormat]) -> VideoFormat? {
        if let hls = formats.first(where: { $0.kind == .hls }) { return hls }
        let muxed = formats
            .filter { $0.kind == .muxed }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let muxedFormat = muxed.first(where: { ($0.height ?? 0) <= 1080 }) ?? muxed.first {
            return muxedFormat
        }
        let videos = formats
            .filter { $0.kind == .videoOnly }
            .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        if let video = videos.first(where: { ($0.height ?? 0) <= 1080 }) ?? videos.first {
            return video
        }
        return formats.first
    }

    private func setOrReplaceItem(_ item: AVPlayerItem) {
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        playerLayerView.playerLayer.player = player
        syncPlayState()
        startTimeObserver()
    }

    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func registerRemoteCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.togglePlayPause()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.togglePlayPause()
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.togglePlayPause()
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentAuthor,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime
        ]
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Cached artwork (thumbnail) shown on the lock screen / Control Center.
    private var nowPlayingArtwork: MPMediaItemArtwork?

    func loadArtwork(for stream: StreamItem) async {
        guard let url = stream.thumbnailURL else { return }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingArtwork = artwork
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func localCompositionItem(video: URL, audio: URL, fallbackDuration: TimeInterval) async -> AVPlayerItem? {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        guard let videoSource = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        var range = CMTimeRange(start: .zero, duration: CMTime(seconds: fallbackDuration, preferredTimescale: 600))
        if let assetDuration = try? await videoAsset.load(.duration), assetDuration.isValid, assetDuration.seconds > 0 {
            range = CMTimeRange(start: .zero, duration: assetDuration)
        }
        do {
            try videoTrack.insertTimeRange(range, of: videoSource, at: .zero)
        } catch {
            return nil
        }
        if let audioSource = try? await audioAsset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(range, of: audioSource, at: .zero)
        }
        return AVPlayerItem(asset: composition)
    }
}

/// A `UIView` whose backing layer is an `AVPlayerLayer`, so the inline video
/// surface can drive an `AVPictureInPictureController`.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    init() {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Observes `AVPictureInPictureController` lifecycle so `PlayerModel.isPiPActive`
/// stays in sync with the real system state (the toolbar button toggles on it).
/// PiP start/stop also drives `PlayerModel.videoOutput` (`.pip` ↔ `.normal`).
private final class PlayerPiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var onStateChange: ((Bool) -> Void)?

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChange?(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        onStateChange?(false)
    }
}
