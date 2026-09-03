import AVFoundation
import AVKit
import MediaPlayer
import Observation

@Observable
@MainActor
final class PlayerModel {
    var player: AVPlayer?
    var currentTitle = ""
    var currentAuthor = ""
    var currentLabel = ""
    var isPlaying = false
    var currentStream: StreamItem?
    var hasItem: Bool { player != nil }

    var queue: [QueueItem] = []
    var queueIndex = 0
    private var endObserver: NSObjectProtocol?

    func playQueue(_ items: [QueueItem], startAt: Int = 0) {
        guard !items.isEmpty else { return }
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
            queueIndex += 1
            let next = queue[queueIndex]
            play(stream: next.stream, formats: next.formats, prefer: next.prefer)
            registerEndObserver()
        } else {
            queue = []
            queueIndex = 0
            removeEndObserver()
        }
    }

    func onItemEnded() {
        playNext()
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
        setOrReplaceItem(item)
        currentLabel = chosen.label
        isPlaying = true
        updateNowPlaying()
        NSLog("iPipe: playing %@ via %@ (%@)", stream.id, chosen.kind.rawValue, chosen.label)
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentStream = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func reactivateAudioSession() {
        setupAudioSession()
        player?.play()
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
        setOrReplaceItem(item)
        isPlaying = true
        updateNowPlaying()
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
        player?.play()
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentAuthor,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
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