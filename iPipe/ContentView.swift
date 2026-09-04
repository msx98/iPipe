import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    /// Clearance above the miniplayer so scroll content ends with a comfortable
    /// margin (more than the miniplayer's height) instead of scrolling under it.
    private static let miniPlayerClearance: CGFloat = 56
    private static let miniPlayerGap: CGFloat = 8

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            TabView(selection: Binding(
                get: { app.rootTab },
                set: { app.rootTab = $0 }
            )) {
                tabContent(TrendingView())
                    .tabItem { Label("Trending", systemImage: "flame.fill") }
                    .tag(AppModel.RootTab.trending)

                tabContent(SearchView())
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppModel.RootTab.search)

                tabContent(SubscriptionsView())
                    .tabItem { Label("Subscriptions", systemImage: "person.2.fill") }
                    .tag(AppModel.RootTab.subscriptions)

                tabContent(PlaylistsView())
                    .tabItem { Label("Playlists", systemImage: "list.bullet") }
                    .tag(AppModel.RootTab.playlists)

                tabContent(SettingsView())
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(AppModel.RootTab.settings)
            }
            .tint(Theme.accent)
            .onOpenURL { url in app.handleDeepLink(url) }

            if let stream = app.focusedVideo {
                VideoPlayerOverlay(stream: stream)
                    .id(stream.id)
                    .transition(.opacity)
            }
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: $app.showQueueCover) {
            NavigationStack {
                QueueScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                app.showQueueCover = false
                            }
                            .tint(Theme.topBarButtonColor)
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
                            .tint(Theme.topBarButtonColor)
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

    /// Applies the mini-player bottom inset to each tab's content. This must be
    /// done per-tab (not on the `TabView` itself): a `TabView` is backed by a
    /// `UITabBarController`, so a `safeAreaInset` applied at that level does not
    /// propagate into the inner `NavigationStack` → `ScrollView`/`Form`/`List`,
    /// letting scroll content run underneath the mini player. Applied inside a
    /// tab, the inset reaches the scroll containers and content stops above it.
    @ViewBuilder
    private func tabContent<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if app.player.hasItem && app.focusedVideo == nil {
                VStack(spacing: 0) {
                    Spacer(minLength: 0).frame(height: Self.miniPlayerClearance)
                    MiniPlayerBar(
                        onOpen: { if let stream = app.player.currentStream { app.focusedVideo = stream } },
                        onClose: { app.player.stop() }
                    )
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, Self.miniPlayerGap)
            }
        }
    }
}

#Preview {
    ContentView().environment(AppModel())
}