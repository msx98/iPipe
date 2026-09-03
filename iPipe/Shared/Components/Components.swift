import SwiftUI

struct StreamCard: View {
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
            }
        }
    }
}

struct ChannelRow: View {
    let channel: ChannelItem

    var body: some View {
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
                Image(systemName: app.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
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
