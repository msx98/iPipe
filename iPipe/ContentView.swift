import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

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
                ForEach(visibleTabs, id: \.self) { tab in
                    tabContent(view(for: tab))
                        .tabItem { Label(label(for: tab), systemImage: systemImage(for: tab)) }
                        .tag(tab)
                }
            }
            .tint(Theme.accent)
            .onOpenURL { url in app.handleDeepLink(url) }
            .onChange(of: scenePhase) { _, phase in
                app.player.updateAppForegrounded(phase == .active)
            }

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

    /// Tabs to render, derived from the persisted snapshot kept in `app`. The
    /// layout is fixed for the session (restart-to-apply), so `hiddenTabs` is
    /// read from the launch snapshot rather than live preferences.
    private var visibleTabs: [AppModel.RootTab] {
        var tabs = app.tabOrder.filter { !app.hiddenTabs.contains($0) }
        if !tabs.contains(.settings) {
            tabs.append(.settings)
        }
        return tabs
    }

    @ViewBuilder
    private func view(for tab: AppModel.RootTab) -> some View {
        switch tab {
        case .trending: TrendingView()
        case .search: SearchView()
        case .subscriptions: SubscriptionsView()
        case .playlists: PlaylistsView()
        case .settings: SettingsView()
        }
    }

    private func label(for tab: AppModel.RootTab) -> String {
        switch tab {
        case .trending: return "Trending"
        case .search: return "Search"
        case .subscriptions: return "Subscriptions"
        case .playlists: return "Playlists"
        case .settings: return "Settings"
        }
    }

    private func systemImage(for tab: AppModel.RootTab) -> String {
        switch tab {
        case .trending: return "flame.fill"
        case .search: return "magnifyingglass"
        case .subscriptions: return "person.2.fill"
        case .playlists: return "list.bullet"
        case .settings: return "gearshape.fill"
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