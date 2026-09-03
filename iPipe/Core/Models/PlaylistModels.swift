import Foundation

struct LocalPlaylistItem: Identifiable, Codable, Hashable {
    var id: String
    var stream: StreamItem
}

struct LocalPlaylist: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var thumbnailStreamID: String?
    var streams: [LocalPlaylistItem]
}

extension LocalPlaylist {
    var streamCount: Int { streams.count }

    var totalDuration: TimeInterval {
        streams.reduce(0) { $0 + ($1.stream.duration ?? 0) }
    }

    var thumbnailURL: URL? {
        if let explicit = thumbnailStreamID,
           let match = streams.first(where: { $0.stream.id == explicit }) {
            return match.stream.thumbnailURL
        }
        return streams.first?.stream.thumbnailURL
    }
}

enum PlaylistShareMode: String, CaseIterable, Identifiable {
    case justUrls
    case withTitles
    case youtubeTemp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .justUrls: return "Just URLs"
        case .withTitles: return "Titles + URLs"
        case .youtubeTemp: return "YouTube temp playlist"
        }
    }
}

/// A queue element the player needs to actually play. Built from a playlist when "Play all" runs.
struct QueueItem: Hashable {
    var stream: StreamItem
    var formats: [VideoFormat]
    var prefer: VideoFormat?
}
