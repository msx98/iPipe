import AVKit
import SwiftUI

struct DownloadsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.downloads.items.isEmpty {
                ContentUnavailableView(
                    "No downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download videos or audio from a video page.")
                )
            } else {
                List {
                    ForEach(app.downloads.items) { item in
                        row(for: item)
                    }
                    .onDelete { offsets in
                        let targets = offsets.compactMap { index in
                            index < app.downloads.items.count ? app.downloads.items[index] : nil
                        }
                        for item in targets {
                            app.downloads.remove(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
    }

    @ViewBuilder
    private func row(for item: DownloadItem) -> some View {
        switch item.state {
        case .downloading:
            HStack(spacing: 12) {
                Image(systemName: item.kind == .video ? "film" : "music.note")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    ProgressView(value: item.progress)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed:
            HStack(spacing: 12) {
                Image(systemName: item.kind == .video ? "film" : "music.note")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        case .done:
            NavigationLink {
                LocalPlayerView(item: item)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.kind == .video ? "film.fill" : "music.note")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        Text("\(item.kind == .video ? "Video" : "Audio") · \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct LocalPlayerView: View {
    @Environment(AppModel.self) private var app
    let item: DownloadItem

    var body: some View {
        VStack(spacing: 16) {
            if item.videoPath != nil {
                if app.player.hasItem {
                    VideoPlayer(player: app.player.player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ProgressView()
                }
            } else {
                ZStack {
                    Rectangle().fill(Theme.accent.opacity(0.15))
                    Image(systemName: "music.note")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button {
                        app.player.togglePlayPause()
                    } label: {
                        Image(systemName: app.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                }
            }
            Text(item.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(item.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let dir = app.downloads.directory
            let video = item.videoPath.map { dir.appendingPathComponent($0) }
            let audio = item.audioPath.map { dir.appendingPathComponent($0) }
            await app.player.playDownload(video: video, audio: audio, title: item.title, author: item.author, duration: item.duration ?? 0)
        }
    }
}
