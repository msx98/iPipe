import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    private static let miniPlayerHeight: CGFloat = 49
    private static let tabBarHeight: CGFloat = 49

    var body: some View {
        @Bindable var app = app
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

                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "list.bullet") }
                    .tag(AppModel.RootTab.playlists)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(AppModel.RootTab.settings)
            }
            .tint(Theme.accent)
            .onOpenURL { url in app.handleDeepLink(url) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Reserve space so scroll content ends above the miniplayer.
                if app.player.hasItem && app.focusedVideo == nil {
                    Color.clear.frame(height: Self.miniPlayerHeight)
                }
            }

            if app.player.hasItem && app.focusedVideo == nil {
                MiniPlayerBar(
                    onOpen: { if let stream = app.player.currentStream { app.focusedVideo = stream } },
                    onClose: { app.player.stop() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .padding(.bottom, Self.tabBarHeight)
            }

            if let stream = app.focusedVideo {
                VideoPlayerOverlay(stream: stream)
                    .id(stream.id)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $app.showQueueCover) {
            NavigationStack {
                QueueScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                app.showQueueCover = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $app.showDownloadsSheet) {
            NavigationStack {
                DownloadsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                app.showDownloadsSheet = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $app.showHistorySheet) {
            NavigationStack {
                HistoryView()
            }
        }
    }
}

#Preview {
    ContentView().environment(AppModel())
}
