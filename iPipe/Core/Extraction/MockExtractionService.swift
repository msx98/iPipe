import Foundation

struct MockExtractionService: ExtractionService {
    var serviceName: String { "Sample Data" }

    private let sampleStreams: [StreamItem] = [
        StreamItem(id: "aqz-KE-bpKQ", title: "Big Buck Bunny", author: "Blender Foundation", authorId: nil, thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg"), durationText: "9:56", duration: 596, viewCountText: "120M views", publishedText: "14 years ago", description: "A large rabbit takes revenge on three bullying rodents."),
        StreamItem(id: "s7dfOXOnG1k", title: "Elephants Dream", author: "Blender Foundation", authorId: nil, thumbnailURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg"), durationText: "10:53", duration: 653, viewCountText: "45M views", publishedText: "15 years ago", description: "Two strange characters explore a capricious and seemingly infinite machine."),
        StreamItem(id: "LXb3EKWsInQ", title: "Costa Rica in 4K", author: "Jacob + Katie Schwarz", authorId: nil, thumbnailURL: nil, durationText: "5:07", duration: 307, viewCountText: "80M views", publishedText: "7 years ago", description: "Costa Rica filmed in 4K ultra high definition."),
        StreamItem(id: "WEH132cQWYw", title: "For Bigger Blazes", author: "Google Chromecast", authorId: nil, thumbnailURL: nil, durationText: "0:15", duration: 15, viewCountText: "2M views", publishedText: "9 years ago", description: "Chromecast advertisement."),
        StreamItem(id: "9bZkp7q19f0", title: "Sample Music Video", author: "Sample Channel", authorId: nil, thumbnailURL: nil, durationText: "4:13", duration: 253, viewCountText: "1B views", publishedText: "10 years ago", description: "A music video sample."),
        StreamItem(id: "eRsGyueVLvQ", title: "Sintel Trailer", author: "Blender Foundation", authorId: nil, thumbnailURL: nil, durationText: "0:52", duration: 52, viewCountText: "9M views", publishedText: "12 years ago", description: "Trailer for the open movie Sintel."),
        StreamItem(id: "1La4QzGeaaQ", title: "Tears of Steel", author: "Blender Foundation", authorId: nil, thumbnailURL: nil, durationText: "12:14", duration: 734, viewCountText: "5M views", publishedText: "10 years ago", description: "Sci-fi short film shot in Amsterdam."),
        StreamItem(id: "hY7m5jjJ9mM", title: "For Bigger Escapes", author: "Google Chromecast", authorId: nil, thumbnailURL: nil, durationText: "0:15", duration: 15, viewCountText: "1M views", publishedText: "9 years ago", description: "Chromecast advertisement."),
        StreamItem(id: "T4hBOEGl2Y0", title: "Apple Keynote Recap", author: "Sample Channel", authorId: nil, thumbnailURL: nil, durationText: "32:10", duration: 1930, viewCountText: "6M views", publishedText: "1 year ago", description: "Highlights from the latest keynote."),
        StreamItem(id: "kJQP7kiw5Fk", title: "Sample Music Video 2", author: "Sample Artist", authorId: nil, thumbnailURL: nil, durationText: "4:42", duration: 282, viewCountText: "700M views", publishedText: "6 years ago", description: "Another music sample."),
        StreamItem(id: "3AtDnEC4zak", title: "We Are The Ones", author: "Sample Artist", authorId: nil, thumbnailURL: nil, durationText: "3:21", duration: 201, viewCountText: "12M views", publishedText: "3 years ago", description: "Music sample."),
        StreamItem(id: "Jfl1zXQ0Ptc", title: "Nature Documentary Sample", author: "Nature Channel", authorId: nil, thumbnailURL: nil, durationText: "45:02", duration: 2702, viewCountText: "3M views", publishedText: "2 years ago", description: "A journey through the wilderness.")
    ]

    private let sampleChannels: [ChannelItem] = [
        ChannelItem(id: "UCsample1", name: "Blender Foundation", handle: "@blender", avatarURL: nil, subscriberText: "1.2M subscribers", descriptionText: "Open source animation studio.", videoCountText: "480 videos"),
        ChannelItem(id: "UCsample2", name: "Sample Channel", handle: "@sample", avatarURL: nil, subscriberText: "850K subscribers", descriptionText: "Tech reviews and tutorials.", videoCountText: "1,204 videos"),
        ChannelItem(id: "UCsample3", name: "Nature Channel", handle: "@nature", avatarURL: nil, subscriberText: "3.4M subscribers", descriptionText: "Documentaries about the natural world.", videoCountText: "312 videos"),
        ChannelItem(id: "UCsample4", name: "Sample Artist", handle: "@artist", avatarURL: nil, subscriberText: "22M subscribers", descriptionText: "Official music channel.", videoCountText: "156 videos")
    ]

    func trending() async throws -> [StreamItem] {
        try await Task.sleep(nanoseconds: 600_000_000)
        return sampleStreams
    }

    func search(_ query: String, filter: SearchFilter) async throws -> SearchResultKind {
        try await Task.sleep(nanoseconds: 500_000_000)
        let lowered = query.lowercased()
        switch filter {
        case .videos:
            return .streams(sampleStreams.filter { $0.title.lowercased().contains(lowered) || $0.author.lowercased().contains(lowered) || lowered.isEmpty })
        case .channels:
            return .channels(sampleChannels.filter { $0.name.lowercased().contains(lowered) })
        case .playlists:
            return .playlists(sampleStreams.prefix(4).map { PlaylistItem(id: "PL" + $0.id, title: $0.title + " Mix", author: $0.author, thumbnailURL: $0.thumbnailURL, videoCountText: "25 videos") })
        case .all:
            return .streams(sampleStreams.filter { $0.title.lowercased().contains(lowered) || lowered.isEmpty })
        }
    }

    func suggestions(for query: String) async throws -> [String] {
        let base = ["\(query) tutorial", "\(query) 2026", "\(query) reaction", "\(query) full album", "\(query) live"]
        return query.isEmpty ? [] : base
    }

    func streamDetails(id: String) async throws -> (stream: StreamItem, formats: [VideoFormat], related: [StreamItem]) {
        try await Task.sleep(nanoseconds: 400_000_000)
        guard let stream = sampleStreams.first(where: { $0.id == id }) else {
            throw ExtractionError.videoUnavailable("Not found in sample data")
        }
        let formats: [VideoFormat] = [
            VideoFormat(kind: .muxed, url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!, itag: 18, label: "360p · mp4"),
            VideoFormat(kind: .muxed, url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!, itag: 22, label: "720p · mp4"),
            VideoFormat(kind: .audioOnly, url: URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!, itag: 140, label: "Audio · m4a")
        ]
        return (stream, formats, sampleStreams.filter { $0.id != id })
    }

    func channel(id: String) async throws -> (channel: ChannelItem, videos: [StreamItem]) {
        try await Task.sleep(nanoseconds: 500_000_000)
        guard let channel = sampleChannels.first(where: { $0.id == id }) ?? sampleChannels.first else {
            throw ExtractionError.videoUnavailable("Channel not found")
        }
        return (channel, sampleStreams)
    }

    func resolveChannelID(fromHandle handle: String) async throws -> String {
        sampleChannels.first(where: { $0.handle == handle })?.id ?? sampleChannels[0].id
    }
}
