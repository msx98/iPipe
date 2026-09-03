import SwiftUI
import AVKit

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
    var onSwipeDownToCollapse: () -> Void = {}
    var onPlayerDragChanged: ((CGFloat) -> Void)?
    var onPlayerDragEnded: ((DragGesture.Value) -> Void)?
    @State private var model = VideoDetailModel()
    @State private var showDescription = false
    @State private var showAddToPlaylist = false
    @State private var showNewPlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showQueue = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    downloadMenuItem(kind: .video)
                    downloadMenuItem(kind: .audio)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddToPlaylist = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            NavigationStack {
                List {
                    if app.playlists.playlists.isEmpty {
                        Text("No playlists yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(app.playlists.playlists) { playlist in
                            Button {
                                addToPlaylist(playlist)
                                showAddToPlaylist = false
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "list.bullet")
                                        .font(.footnote)
                                        .lineLimit(1)
                                    Spacer()
                                    if isAlreadyInPlaylist(playlist) {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        newPlaylistName = ""
                        showNewPlaylistAlert = true
                        showAddToPlaylist = false
                    } label: {
                        Label("New Playlist…", systemImage: "plus.rectangle.on.folder")
                    }
                }
                .navigationTitle("Add to Playlist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showAddToPlaylist = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("New Playlist", isPresented: $showNewPlaylistAlert) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let target = model.stream ?? stream
                app.playlists.create(newPlaylistName, streams: [target])
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                QueueView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showQueue = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
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
                                NavigationLink(value: related) {
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
                    VideoPlayer(player: app.player.player)
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
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        onPlayerDragChanged?(max(0, value.translation.height))
                    }
                    .onEnded { value in
                        onPlayerDragEnded?(value)
                    }
            )

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

    private func addToPlaylist(_ playlist: LocalPlaylist) {
        let target = model.stream ?? stream
        app.playlists.append([target], to: playlist)
    }

    private func isAlreadyInPlaylist(_ playlist: LocalPlaylist) -> Bool {
        let target = model.stream ?? stream
        return playlist.streams.contains(where: { $0.stream.id == target.id })
    }
}

/// Up-next queue showing the latent playback queue. Mirrors the playlist item
/// interface (thumbnail, title, author), with “Dismiss” in place of delete:
/// dismissing the active item starts the next one or stops when empty.
struct QueueView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.player.queue.isEmpty {
                ContentUnavailableView(
                    "Queue is empty",
                    systemImage: "list.bullet",
                    description: Text("Videos you play and playlists you background land here.")
                )
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
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Up Next")
        .navigationBarTitleDisplayMode(.inline)
    }
}
