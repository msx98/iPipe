import SwiftUI

/// Full-screen queue view. Lists the latent playback queue and pins a sticky
/// playback-control bar at the bottom (seek slider, time labels, previous/-10/
/// play-pause-or-restart/+10/next). Controls are grayed out when nothing is
/// active; when the queue finishes it stays intact and just shows "Not Playing".
struct QueueScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            queueList
            Divider()
            PlaybackControlsBar(
                label: app.player.currentTitle,
                detail: app.player.currentAuthor,
                currentTime: app.player.currentTime,
                duration: app.player.currentDuration,
                isPlaying: app.player.isPlaying,
                hasQueue: !app.player.queue.isEmpty,
                hasActiveVideo: app.player.hasItem,
                queueFinished: app.player.queueFinished
            )
        }
        .background(Color(.systemBackground))
        .navigationTitle("Up Next")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear", role: .destructive) {
                    app.player.clearQueue()
                }
                .disabled(app.player.queue.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if app.player.queue.isEmpty {
            Spacer()
            ContentUnavailableView(
                "Queue is empty",
                systemImage: "list.bullet",
                description: Text("Videos you play and playlists you background land here.")
            )
            Spacer()
        } else {
            List {
                ForEach(Array(app.player.queue.enumerated()), id: \.element.stream.id) { index, item in
                    Button {
                        app.player.playFromQueue(at: index)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncThumbnail(url: item.stream.thumbnailURL, videoId: item.stream.id)
                                .frame(width: 96)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.stream.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                Text(item.stream.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if index == app.player.queueIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            app.player.removeFromQueue(at: index)
                        } label: {
                            Label("Dismiss", systemImage: "xmark.circle")
                        }
                    }
                }
                .onMove { offsets, destination in
                    app.player.moveQueueItem(fromOffsets: offsets, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        }
    }
}

/// Sticky bottom playback controls. Order: previous, back 10s, play/pause
/// (or restart when the queue is finished), forward 10s, next.
private struct PlaybackControlsBar: View {
    @Environment(AppModel.self) private var app
    let label: String
    let detail: String
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let hasQueue: Bool
    let hasActiveVideo: Bool
    let queueFinished: Bool

    private var showPlaybackInfo: Bool { hasActiveVideo && !queueFinished }

    var body: some View {
        VStack(spacing: 10) {
            if showPlaybackInfo {
                currentInfo
                progressSlider
            } else {
                Text("Not Playing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 36) {
                Button {
                    app.player.playPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                .disabled(!showPlaybackInfo)
                .buttonStyle(.plain)
                .accessibilityLabel("Previous")

                Button {
                    app.player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .disabled(!showPlaybackInfo)
                .buttonStyle(.plain)
                .accessibilityLabel("Back 10 seconds")

                middleButton

                Button {
                    app.player.skipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .disabled(!showPlaybackInfo)
                .buttonStyle(.plain)
                .accessibilityLabel("Forward 10 seconds")

                Button {
                    app.player.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
                .disabled(!showPlaybackInfo)
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var middleButton: some View {
        if queueFinished {
            Button {
                app.player.restartQueue()
            } label: {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 44))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restart queue")
        } else {
            Button {
                app.player.togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .disabled(!hasActiveVideo)
            .buttonStyle(.plain)
        }
    }

    private var currentInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.isEmpty ? "Now playing" : label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressSlider: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { min(currentTime, duration) },
                    set: { app.player.seek(to: $0) }
                ),
                in: 0...duration
            )
            .tint(Theme.accent)
            HStack {
                Text(currentTime.durationText)
                Spacer()
                Text(duration.durationText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}