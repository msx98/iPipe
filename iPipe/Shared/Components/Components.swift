import SwiftUI

/// The shared top-right toolbar: Downloads, queue view, and history.
struct StandardToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    var color: Color = Theme.topBarButtonColor
    var showsPiP = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if showsPiP {
                Button {
                    app.player.togglePiP()
                } label: {
                    Image(systemName: app.player.isPiPActive ? "pip.exit" : "pip.enter")
                }
                .accessibilityLabel("Picture in Picture")
                .tint(color)
            }

            Button {
                app.showDownloadsSheet = true
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .accessibilityLabel("Downloads")
            .tint(color)

            Button {
                app.showHistorySheet = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("History")
            .tint(color)

            Button {
                app.showQueueCover = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Up Next")
            .tint(color)
        }
    }
}

/// A view that renders the three standard toolbar buttons (covers cases where
/// ToolbarContent can't be expressed directly, e.g. inside an item group).
struct StandardToolbarGroup: View {
    @Environment(AppModel.self) private var app
    var color: Color = Theme.topBarButtonColor

    var body: some View {
        Button {
            app.showDownloadsSheet = true
        } label: {
            Image(systemName: "arrow.down.circle")
        }
        .accessibilityLabel("Downloads")
        .tint(color)

        Button {
            app.showHistorySheet = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("History")
        .tint(color)

        Button {
            app.showQueueCover = true
        } label: {
            Image(systemName: "list.bullet")
        }
        .accessibilityLabel("Up Next")
        .tint(color)
    }
}

/// Confirmation alert for clearing watch history, shared by the Settings "Data"
/// section and the History popup so both use the same routine.
struct ClearHistoryConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let onClear: () -> Void

    func body(content: Content) -> some View {
        content.alert("Clear watch history?", isPresented: $isPresented) {
            Button("Clear", role: .destructive) { onClear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your watch history will be emptied.")
        }
    }
}

/// A stream row that opens the video on tap and shows the "Add to playlist"
/// dialog on long press.
struct StreamCell: View {
    let stream: StreamItem
    @State private var showAddToPlaylist = false

    var body: some View {
        StreamCard(stream: stream)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                showAddToPlaylist = true
            })
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(stream: stream)
            }
            .accessibilityHint("Long press to add to a playlist")
    }
}

struct StreamCard: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    var showsChannel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncThumbnail(url: stream.thumbnailURL, videoId: stream.id)
                .overlay(alignment: .bottomTrailing) {
                    if let d = stream.durationText {
                        Text(d)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            HStack(alignment: .top, spacing: 10) {
                ChannelAvatar(name: stream.author, url: nil, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if showsChannel, !stream.author.isEmpty {
                        Text(stream.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text([stream.viewCountText, stream.publishedText].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                RowMenu {
                    Button("Open") { app.focusedVideo = stream }
                    Button("Remove from history", role: .destructive) {
                        app.history.removeAll { $0.id == stream.id }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { app.focusedVideo = stream }
    }
}

struct ChannelRow: View {
    @Environment(AppModel.self) private var app
    let channel: ChannelItem

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: channel) {
                HStack(spacing: 12) {
                    ChannelAvatar(name: channel.name, url: channel.avatarURL, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text([channel.handle, channel.subscriberText].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            RowMenu {
                NavigationLink(destination: ChannelView(channel: channel)) {
                    Label("Visit channel", systemImage: "person.2")
                }
                Button("Unsubscribe", role: .destructive) { app.toggleSubscription(channel) }
            }
        }
        .contentShape(Rectangle())
    }
}

struct ChannelAvatar: View {
    let name: String
    let url: URL?
    var size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.2))
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
    }
}

struct AsyncThumbnail: View {
    let url: URL?
    var videoId: String = ""

    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "play.rectangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            } else {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct LoadingFooter: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var app

    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        if app.player.hasItem, let stream = app.player.currentStream {
            label(stream: stream)
        }
    }

    @ViewBuilder
    private func label(stream: StreamItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: app.player.currentLabel.contains("Audio") ? "music.note" : "play.rectangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.player.currentTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(app.player.currentAuthor)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                app.player.togglePlayPause()
            } label: {
                Image(systemName: app.player.playState ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -60 || value.predictedEndTranslation.height < -40 {
                        onOpen()
                    }
                }
        )
    }
}

/// Transient confirmation shown at the bottom of the video detail screen after a
/// "Copy link" action: a dark pill with a green checkmark, animating in and out.
/// Shared by the video detail screen and list cells so both give the same
/// feedback when a link is copied to the clipboard.
struct CopyLinkToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Link copied")
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.init(white: 0.16, alpha: 1.0)), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .padding(.bottom, 32)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A trailing three-dot (ellipsis) icon button that opens a `Menu`. Used on every
/// list row so each row exposes the same "Open" / "Delete" context menu; it
/// replaces the plain chevron that previously only signalled navigation.
struct RowMenu<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }
}
