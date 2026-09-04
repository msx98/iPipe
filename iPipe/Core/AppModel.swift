import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    enum Backend: String, CaseIterable, Identifiable {
        case youtube = "YouTube (InnerTube)"
        case sample = "Sample Data"

        var id: String { rawValue }
    }

    enum RootTab: String, CaseIterable, Identifiable, Hashable, Codable {
        case trending, search, subscriptions, playlists, settings
        var id: String { rawValue }
    }

    var rootTab: RootTab = .trending
    var trendingPath = NavigationPath()
    var searchPath = NavigationPath()
    var subscriptionsPath = NavigationPath()
    var playlistsPath = NavigationPath()
    var settingsPath = NavigationPath()

    /// Global sheet/cover state driven by the shared toolbar.
    var showDownloadsSheet = false
    var showHistorySheet = false
    var showQueueCover = false

    /// When non-nil, the full video preview page is presented (focused). Drives
    /// both the full-screen cover and whether the mini player is visible.
    var focusedVideo: StreamItem?

    private(set) var backend: Backend
    var extraction: ExtractionService { backend == .youtube ? InnerTubeClient() : MockExtractionService() }

    let player = PlayerModel()
    let downloads = DownloadManager()
    let playlists = LocalPlaylistManager()
    private(set) var signedIn: Bool = false

    var subscriptions: [ChannelItem]
    var history: [StreamItem]
    private(set) var colorSchemeChoice: String

    /// Persisted tab layout. Loaded as a snapshot at init and consumed by
    /// ContentView; changes made in Settings only take effect after relaunch.
    private(set) var tabOrder: [RootTab]
    private(set) var hiddenTabs: Set<RootTab>

    private static let subscriptionsKey = "np.subscriptions"
    private static let historyKey = "np.history"
    private static let backendKey = "np.backend"
    private static let schemeKey = "np.colorScheme"
    private static let tabOrderKey = "np.tabOrder"
    private static let hiddenTabsKey = "np.hiddenTabs"
    private static let defaultTabOrder: [RootTab] = [.trending, .search, .subscriptions, .playlists, .settings]

    init() {
        let defaults = UserDefaults.standard
        backend = Backend(rawValue: defaults.string(forKey: Self.backendKey) ?? "") ?? .youtube
        colorSchemeChoice = defaults.string(forKey: Self.schemeKey) ?? "system"
        tabOrder = Self.loadTabOrder(defaults)
        hiddenTabs = Self.loadHiddenTabs(defaults)
        if let data = defaults.data(forKey: Self.subscriptionsKey),
           let decoded = try? JSONDecoder().decode([ChannelItem].self, from: data) {
            subscriptions = decoded
        } else {
            subscriptions = [
                ChannelItem(id: "UCX6OQ3DkcsbYNE6H8uQQuVA", name: "MrBeast", handle: "@MrBeast", avatarURL: nil, subscriberText: "300M+ subscribers", descriptionText: "", videoCountText: nil),
                ChannelItem(id: "UCsBjZrXhCxSGB1W9wR2N8fA", name: "Marques Brownlee", handle: "@mkbhd", avatarURL: nil, subscriberText: "19M subscribers", descriptionText: "", videoCountText: nil)
            ]
        }
        if let data = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([StreamItem].self, from: data) {
            history = decoded
        } else {
            history = []
        }
        // Sideloaded cookies (make install COOKIESFILE=…) land in Documents/
        // before first launch; import them into the keychain, then delete the file.
        CookieStore.shared.ingestDroppedFile()
        refreshSignedIn()
    }

    func refreshSignedIn() {
        signedIn = CookieStore.shared.isSignedIn
    }

    private static func loadTabOrder(_ defaults: UserDefaults) -> [RootTab] {
        guard let data = defaults.data(forKey: tabOrderKey),
              let decoded = try? JSONDecoder().decode([RootTab].self, from: data),
              !decoded.isEmpty else {
            return defaultTabOrder
        }
        return decoded
    }

    private static func loadHiddenTabs(_ defaults: UserDefaults) -> Set<RootTab> {
        guard let data = defaults.data(forKey: hiddenTabsKey),
              let decoded = try? JSONDecoder().decode([RootTab].self, from: data) else {
            return []
        }
        return Set(decoded).subtracting([.settings])
    }

    /// Persists a new tab layout to `UserDefaults` without mutating the in-memory
    /// snapshot, so changes only take effect after the next launch. `.settings`
    /// is always kept present and visible.
    func saveTabConfiguration(order: [RootTab], hidden: Set<RootTab>) {
        var resultOrder: [RootTab] = []
        for tab in order where !resultOrder.contains(tab) {
            resultOrder.append(tab)
        }
        if !resultOrder.contains(.settings) {
            resultOrder.append(.settings)
        }
        let safeHidden = hidden.subtracting([.settings])
        if let data = try? JSONEncoder().encode(resultOrder) {
            UserDefaults.standard.set(data, forKey: Self.tabOrderKey)
        }
        if let data = try? JSONEncoder().encode(Array(safeHidden)) {
            UserDefaults.standard.set(data, forKey: Self.hiddenTabsKey)
        }
    }

    /// Handles an `ipipe://<youtube_link_or_hash>` URL: resolves it to a video
    /// or channel target, pushes it onto the Search navigation stack, and
    /// brings that tab forward so the link opens in-app.
    func handleDeepLink(_ url: URL) {
        Log.url(url.absoluteString)
        guard url.scheme?.lowercased() == DeepLink.scheme.lowercased() else { return }
        guard let target = DeepLink.parse(DeepLink.payload(from: url)) else {
            NSLog("iPipe: deep link could not be parsed: %@", url.absoluteString)
            return
        }
        switch target {
        case .video(let item):
            focusedVideo = item
        case .channel(let channel):
            searchPath.append(channel)
        }
        rootTab = .search
    }

    func setBackend(_ newBackend: Backend) {
        backend = newBackend
        UserDefaults.standard.set(newBackend.rawValue, forKey: Self.backendKey)
    }

    func setColorScheme(_ choice: String) {
        colorSchemeChoice = choice
        UserDefaults.standard.set(choice, forKey: Self.schemeKey)
    }

    func recordWatch(_ item: StreamItem) {
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    func isSubscribed(_ channel: ChannelItem) -> Bool {
        subscriptions.contains { $0.id == channel.id }
    }

    func toggleSubscription(_ channel: ChannelItem) {
        if isSubscribed(channel) {
            subscriptions.removeAll { $0.id == channel.id }
        } else {
            subscriptions.insert(channel, at: 0)
        }
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Self.subscriptionsKey)
        }
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }
}
