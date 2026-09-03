import Foundation

enum Log {
    /// Logs the URL of a visited window / window-like surface (video detail
    /// views, channel pages, WebView navigations, deep links, …).
    static func url(_ string: String) {
        NSLog("iPipe: open \(string)")
    }
}
