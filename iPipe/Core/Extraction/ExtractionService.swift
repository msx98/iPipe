import Foundation

protocol ExtractionService {
    var serviceName: String { get }
    func trending() async throws -> [StreamItem]
    func search(_ query: String, filter: SearchFilter) async throws -> SearchResultKind
    func suggestions(for query: String) async throws -> [String]
    func streamDetails(id: String) async throws -> (stream: StreamItem, formats: [VideoFormat], related: [StreamItem])
    func channel(id: String) async throws -> (channel: ChannelItem, videos: [StreamItem])
    func resolveChannelID(fromHandle handle: String) async throws -> String
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case channels = "Channels"
    case playlists = "Playlists"

    var id: String { rawValue }
}
