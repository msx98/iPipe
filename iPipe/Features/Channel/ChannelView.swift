import SwiftUI

@Observable
@MainActor
final class ChannelModel {
    var channel: ChannelItem?
    var videos: [StreamItem] = []
    var isLoading = true
    var error: String?
    var loadedID: String?

    func load(app: AppModel, channel: ChannelItem) async {
        if loadedID == channel.id { return }
        isLoading = true
        error = nil
        do {
            let id = channel.id.hasPrefix("UC") ? channel.id : try await app.extraction.resolveChannelID(fromHandle: channel.handle ?? channel.name)
            let result = try await app.extraction.channel(id: id)
            self.channel = result.channel
            videos = result.videos
            loadedID = channel.id
        } catch {
            self.error = error.localizedDescription
            self.channel = channel
            loadedID = nil
        }
        isLoading = false
    }
}

struct ChannelView: View {
    @Environment(AppModel.self) private var app
    let channel: ChannelItem
    @State private var model = ChannelModel()

    var body: some View {
        Group {
            if let error = model.error, model.videos.isEmpty {
                ErrorStateView(message: error) {
                    model.loadedID = nil
                    Task { await model.load(app: app, channel: channel) }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        header
                        if model.isLoading {
                            ProgressView()
                        } else {
                            ForEach(model.videos) { video in
                                Button {
                                    app.focusedVideo = video
                                } label: {
                                    StreamCard(stream: video, showsChannel: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(model.channel?.name ?? channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { StandardToolbar() }
        .task {
            await model.load(app: app, channel: channel)
            Log.url(YouTubeURLs.channel(model.channel ?? channel))
        }
    }

    private var header: some View {
        let displayChannel = model.channel ?? channel
        let subscribed = app.isSubscribed(displayChannel)
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                ChannelAvatar(name: displayChannel.name, url: displayChannel.avatarURL, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayChannel.name).font(.title3.weight(.bold)).lineLimit(1)
                    if let subs = displayChannel.subscriberText {
                        Text(subs).font(.caption).foregroundStyle(.secondary)
                    }
                    if let count = displayChannel.videoCountText {
                        Text(count).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Button {
                app.toggleSubscription(displayChannel)
            } label: {
                Label(subscribed ? "Subscribed" : "Subscribe", systemImage: subscribed ? "bell.fill" : "bell")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(subscribed ? Color(.secondarySystemFill) : Theme.accent, in: Capsule())
                    .foregroundStyle(subscribed ? Color.primary : Color.white)
            }
            .buttonStyle(.plain)
        }
    }
}
