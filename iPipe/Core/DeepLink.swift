import Foundation
import SwiftUI

enum DeepLinkTarget: Hashable {
    case video(StreamItem)
    case channel(ChannelItem)
}

/// Resolves `ipipe://<youtube_link_or_hash>` payloads into navigable targets.
enum DeepLink {
    static let scheme = "ipipe"
    private static let urlPrefix = "\(scheme)://"

    /// Everything after the `ipipe://` authority.
    static func payload(from url: URL) -> String {
        let abs = url.absoluteString
        if abs.hasPrefix(urlPrefix) {
            return String(abs.dropFirst(urlPrefix.count))
        }
        return abs
    }

    static func parse(_ raw: String) -> DeepLinkTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http") || lower.contains("youtu.be") || trimmed.contains("?") || trimmed.contains("/") {
            return parseURL(trimmed)
        }
        if trimmed.hasPrefix("@") {
            return channelTarget(handle: trimmed)
        }
        return videoTarget(id: trimmed, title: "Loading video…")
    }

    private static func parseURL(_ s: String) -> DeepLinkTarget? {
        var candidate = s
        if !candidate.hasPrefix("http") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate) else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path

        if path.hasPrefix("/@") {
            return channelTarget(handle: String(path.dropFirst()))
        }

        let segments = path.split(separator: "/").map(String.init)
        if segments.count >= 2,
           let seg0 = segments.first,
           (seg0 == "channel" || seg0 == "c" || seg0 == "user"),
           let rest = segments.dropFirst().first {
            if seg0 == "channel" {
                return channelTarget(id: rest)
            } else {
                return channelTarget(handle: "@" + rest)
            }
        }

        if let query = url.query {
            for pair in query.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if String(kv[0]) == "v", kv.count > 1 {
                    let decoded = kv[1].removingPercentEncoding ?? String(kv[1])
                    if !decoded.isEmpty {
                        return videoTarget(id: decoded, title: "Loading video…")
                    }
                }
            }
        }

        if host == "youtu.be" || host.hasSuffix("youtu.be") {
            let id = path.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty {
                return videoTarget(id: id, title: "Loading video…")
            }
        }
        return nil
    }

    private static func videoTarget(id: String, title: String) -> DeepLinkTarget {
        .video(StreamItem(
            id: id,
            title: title,
            author: "",
            thumbnailURL: nil,
            durationText: nil,
            duration: nil,
            viewCountText: nil,
            publishedText: nil
        ))
    }

    private static func channelTarget(id: String) -> DeepLinkTarget {
        .channel(ChannelItem(
            id: id,
            name: id,
            handle: nil,
            avatarURL: nil,
            subscriberText: nil,
            descriptionText: "",
            videoCountText: nil
        ))
    }

    private static func channelTarget(handle: String) -> DeepLinkTarget {
        .channel(ChannelItem(
            id: "",
            name: handle,
            handle: handle,
            avatarURL: nil,
            subscriberText: nil,
            descriptionText: "",
            videoCountText: nil
        ))
    }
}
