import Foundation

enum YouTubeURLs {
    static func video(_ id: String) -> String {
        "https://www.youtube.com/watch?v=\(id)"
    }

    static func channel(_ c: ChannelItem) -> String {
        if let handle = c.handle, !handle.isEmpty {
            let h = handle.hasPrefix("@") ? handle : "@" + handle
            return "https://www.youtube.com/\(h)"
        }
        if !c.id.isEmpty {
            return "https://www.youtube.com/channel/\(c.id)"
        }
        let q = c.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? c.name
        return "https://www.youtube.com/results?searchQuery=\(q)"
    }
}
