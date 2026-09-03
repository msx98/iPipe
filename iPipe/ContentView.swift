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

                    PlaylistsView()
                        .tabItem { Label("Playlists", systemImage: "list.bullet") }
                        .tag(AppModel.RootTab.playlists)

                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(AppModel.RootTab.settings)
                }
                .tint(Theme.accent)
                .onOpenURL { url in app.handleDeepLink(url) }

                if app.player.hasItem && app.focusedVideo == nil {
                    MiniPlayerBar(
                        onOpen: { if let stream = app.player.currentStream { app.focusedVideo = stream } },
                        onClose: { app.player.stop() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 88 + geo.safeAreaInsets.bottom)
                }

                if let stream = app.focusedVideo {
                    VideoPlayerOverlay(stream: stream)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

#Preview {
    ContentView().environment(AppModel())
}
