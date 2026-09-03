import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TabView(selection: Binding(
                    get: { app.rootTab },
                    set: { app.rootTab = $0 }
                )) {
                    TrendingView()
                        .tabItem { Label("Trending", systemImage: "flame.fill") }
                        .tag(AppModel.RootTab.trending)

                    SearchView()
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                        .tag(AppModel.RootTab.search)

                    SubscriptionsView()
                        .tabItem { Label("Subscriptions", systemImage: "person.2.fill") }
                        .tag(AppModel.RootTab.subscriptions)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(AppModel.RootTab.settings)
                }
                .tint(Theme.accent)
                .onOpenURL { url in app.handleDeepLink(url) }
                .fullScreenCover(item: $app.focusedVideo) { stream in
                    NavigationStack {
                        VideoDetailView(stream: stream)
                            .navigationDestination(for: StreamItem.self) { related in
                                VideoDetailView(stream: related)
                            }
                            .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        app.focusedVideo = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                }
                            }
                    }
                }

                if app.player.hasItem && app.focusedVideo == nil {
                    MiniPlayerBar()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 88 + geo.safeAreaInsets.bottom)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.player.hasItem {
            Button {
                if let stream = app.player.currentStream {
                    app.focusedVideo = stream
                }
            } label: {
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
                        app.player.stop()
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
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
    }
}

#Preview {
    ContentView().environment(AppModel())
}
