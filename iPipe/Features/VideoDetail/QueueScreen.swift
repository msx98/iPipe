import SwiftUI

/// Full-screen queue view. Lists the latent playback queue and pins a sticky
/// playback-control bar at the bottom (seek slider, time labels, skip/forward/
/// previous/toggle play-pause). Controls are grayed out when the queue is empty.
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
                isLast: app.player.queueIndex >= max(0, app.player.queue.count - 1)
            )
        }
        .background(Color(.systemBackground))
        .navigationTitle("Up Next")
        .navigationBarTitleDisplayMode(.inline)
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
            }
            .listStyle(.plain)
        }
    }
}

/// Sticky bottom playback controls.
private struct PlaybackControlsBar: View {
    @Environment(AppModel.self) private var app
    let label: String
    let detail: String
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let hasQueue: Bool
    let hasActiveVideo: Bool
    let isLast: Bool

    var body: some View {
        VStack(spacing: 10) {
            if hasActiveVideo {
                currentInfo
                progressSlider
            } else {
                Text("Nothing playing")
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
                .disabled(!hasActiveVideo)
                .buttonStyle(.plain)

                Button {
                    app.player.playNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                }
                .disabled(!hasQueue)
                .buttonStyle(.plain)

                Button {
                    app.player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .disabled(!hasActiveVideo)
                .buttonStyle(.plain)

                Button {
                    app.player.togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(!hasActiveVideo)
                .buttonStyle(.plain)

                Button {
                    app.player.skipForward()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .disabled(!hasActiveVideo)
                .buttonStyle(.plain)

                Button {
                    app.player.playFromQueue(at: app.player.queueIndex)
                } label: {
                    Image(systemName: isLast ? "arrow.clockwise" : "arrow.right.to.line")
                        .font(.title2)
                }
                .disabled(hasQueue && !hasActiveVideo)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
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