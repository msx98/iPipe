import Foundation

struct StreamItem: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var author: String
    var authorId: String?
    var thumbnailURL: URL?
    var durationText: String?
    var duration: TimeInterval?
    var viewCountText: String?
    var publishedText: String?
    var description: String = ""

    static func == (lhs: StreamItem, rhs: StreamItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

struct ChannelItem: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var handle: String?
    var avatarURL: URL?
    var subscriberText: String?
    var descriptionText: String = ""
    var videoCountText: String?
}

struct PlaylistItem: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var author: String
    var thumbnailURL: URL?
    var videoCountText: String?
}

struct CommentItem: Identifiable, Hashable {
    var id: String
    var author: String
    var avatarURL: URL?
    var text: String
    var publishedText: String?
    var likeCountText: String?
    var replyCount: Int
}

struct VideoFormat: Identifiable, Hashable {
    enum Kind: String { case hls, muxed, videoOnly, audioOnly }
    var id: String { "\(kind.rawValue)-\(itag ?? 0)-\(label)" }
    var kind: Kind
    var url: URL
    var itag: Int?
    var label: String
    var height: Int? = nil
    var width: Int? = nil
    var contentLength: Int64? = nil
    var isAudioOnly: Bool { kind == .audioOnly }
}

enum SearchResultKind {
    case streams([StreamItem])
    case channels([ChannelItem])
    case playlists([PlaylistItem])
}

enum ExtractionError: LocalizedError {
    case requestFailed(Int)
    case parsingFailed(String)
    case videoUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code): return "Request failed (HTTP \(code))"
        case .parsingFailed(let detail): return "Could not parse response: \(detail)"
        case .videoUnavailable(let reason): return reason
        }
    }
}
