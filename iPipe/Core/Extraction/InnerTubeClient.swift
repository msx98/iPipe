import Foundation
import CommonCrypto

struct InnerTubeClient: ExtractionService {
    var serviceName: String { "YouTube" }

    private let session: URLSession
    private var hl: String
    private var gl: String

    private static let clientName = "IOS"
    private static let clientVersion = "20.10.4"
    private static let deviceModel = "iPhone16,2"
    private static let osVersion = "18.3.2.22D82"
    private static let userAgent = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)"
    private static let webClientVersion = "2.20250312.04.00"
    private static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    private static let androidUserAgent = "com.google.android.youtube/20.10.4 (Linux; U; Android 15) gzip"
    private static let videosTabParams = "EgZ2aWRlb3PyBgQKAjoA"
    private static let homeChannelIDs = [
        "UCX6OQ3DkcsbYNE6H8uQQuVA",
        "UCHnyfMqiRRG1u-2MsSQLbXA",
        "UCsXVk37bltHxD1rDPwtNM8Q",
        "UCBJycsmduvYEL83R_U4JriQ",
        "UCLA_DiR1FfKNvjuUpBHmylQ",
        "UCAuUUnT6oDeKwE6v1NGQxug"
    ]

    init(hl: String = "en", gl: String = "US") {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        self.hl = hl
        self.gl = gl
    }

    private enum ClientKind {
        case ios
        case web
        case android
    }

    private func call(endpoint: String, body: [String: Any], client: ClientKind = .web) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var clientInfo: [String: Any]
        switch client {
        case .ios:
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            clientInfo = [
                "clientName": Self.clientName,
                "clientVersion": Self.clientVersion,
                "deviceMake": "Apple",
                "deviceModel": Self.deviceModel,
                "osName": "iPhone OS",
                "osVersion": Self.osVersion,
                "hl": hl,
                "gl": gl,
                "utcOffsetMinutes": 0
            ]
        case .web:
            request.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
            clientInfo = [
                "clientName": "WEB",
                "clientVersion": Self.webClientVersion,
                "hl": hl,
                "gl": gl
            ]
        case .android:
            request.setValue(Self.androidUserAgent, forHTTPHeaderField: "User-Agent")
            clientInfo = [
                "clientName": "ANDROID",
                "clientVersion": Self.clientVersion,
                "androidSdkVersion": 35,
                "hl": hl,
                "gl": gl
            ]
        }
        var payload = body
        payload["context"] = [
            "client": clientInfo,
            "user": ["lockedSafetyMode": false],
            "request": ["useSsl": true]
        ]
        if CookieStore.shared.isSignedIn {
            if let cookieHeader = CookieStore.shared.cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            if let sapisid = CookieStore.shared.sapisid {
                let origin = "https://www.youtube.com"
                let ts = Int(Date().timeIntervalSince1970)
                let hash = Self.sha1("\(ts) \(sapisid) \(origin)")
                request.setValue("SAPISIDHASH \(ts)_\(hash)", forHTTPHeaderField: "Authorization")
                request.setValue(origin, forHTTPHeaderField: "X-Origin")
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExtractionError.requestFailed(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ExtractionError.requestFailed(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.parsingFailed("not a JSON object")
        }
        return json
    }

    private static func sha1(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ExtractionError.requestFailed(code)
        }
        return data
    }
}

extension InnerTubeClient {

    func trending() async throws -> [StreamItem] {
        var results: [[StreamItem]] = []
        try await withThrowingTaskGroup(of: [StreamItem].self) { group in
            for id in Self.homeChannelIDs {
                group.addTask {
                    let json = try await self.call(endpoint: "browse", body: [
                        "browseId": id,
                        "params": Self.videosTabParams
                    ])
                    return Self.collectVideos(in: json)
                }
            }
            for try await items in group {
                results.append(items)
            }
        }
        var merged: [StreamItem] = []
        var seen = Set<String>()
        var index = 0
        while merged.count < 60 {
            var addedThisRound = false
            for list in results {
                guard index < list.count else { continue }
                let item = list[index]
                if !seen.contains(item.id) {
                    seen.insert(item.id)
                    merged.append(item)
                    addedThisRound = true
                }
            }
            if !addedThisRound { break }
            index += 1
        }
        guard !merged.isEmpty else {
            throw ExtractionError.parsingFailed("home feed came back empty")
        }
        return merged
    }

    func search(_ query: String, filter: SearchFilter) async throws -> SearchResultKind {
        var body: [String: Any] = ["query": query]
        switch filter {
        case .all: break
        case .videos: body["params"] = "EgIQAQ%3D%3D"
        case .channels: body["params"] = "EgIQAg%3D%3D"
        case .playlists: body["params"] = "EgIQAw%3D%3D"
        }
        let json = try await call(endpoint: "search", body: body)
        let videos = Self.collectVideos(in: json)
        let channels = Self.collectChannels(in: json)
        let playlists = Self.collectPlaylists(in: json)
        switch filter {
        case .videos: return .streams(videos)
        case .channels: return .channels(channels)
        case .playlists: return .playlists(playlists)
        case .all:
            if !videos.isEmpty { return .streams(videos) }
            if !channels.isEmpty { return .channels(channels) }
            return .playlists(playlists)
        }
    }

    func suggestions(for query: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "hl", value: hl),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components.url else { return [] }
        let data = try await get(url: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count > 1 else { return [] }
        if let flat = json[1] as? [String] {
            return flat
        }
        if let nested = json[1] as? [[Any]] {
            return nested.compactMap { $0.first as? String }
        }
        return []
    }

    func streamDetails(id: String) async throws -> (stream: StreamItem, formats: [VideoFormat], related: [StreamItem]) {
        let json = try await call(endpoint: "player", body: [
            "videoId": id,
            "contentCheckOk": true,
            "racyCheckOk": true
        ], client: .ios)
        let status = json["playabilityStatus"] as? [String: Any]
        if let statusStatus = status?["status"] as? String, statusStatus != "OK" {
            let reason = status?["reason"] as? String ?? "Video unavailable"
            throw ExtractionError.videoUnavailable(reason)
        }

        let videoDetails = json["videoDetails"] as? [String: Any] ?? [:]
        let lengthSeconds = (videoDetails["lengthSeconds"] as? String).flatMap(TimeInterval.init)
        let stream = StreamItem(
            id: id,
            title: videoDetails["title"] as? String ?? "Untitled",
            author: videoDetails["author"] as? String ?? "",
            authorId: videoDetails["channelId"] as? String,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            durationText: lengthSeconds.map(Self.formatDuration),
            duration: lengthSeconds,
            viewCountText: (videoDetails["viewCount"] as? String).map { "\($0) views" },
            publishedText: nil,
            description: videoDetails["shortDescription"] as? String ?? ""
        )

        var formats: [VideoFormat] = []
        let streamingData = json["streamingData"] as? [String: Any] ?? [:]
        if let hls = streamingData["hlsManifestUrl"] as? String, let url = URL(string: hls) {
            formats.append(VideoFormat(kind: .hls, url: url, itag: nil, label: "Adaptive (HLS)"))
        }
        let muxed = streamingData["formats"] as? [[String: Any]] ?? []
        formats.append(contentsOf: Self.parseFormats(muxed))
        let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []
        formats.append(contentsOf: Self.parseFormats(adaptive, isAdaptive: true))

        let androidJSON = try? await call(endpoint: "player", body: [
            "videoId": id,
            "contentCheckOk": true,
            "racyCheckOk": true
        ], client: .android)
        if let androidStreamingData = androidJSON?["streamingData"] as? [String: Any] {
            let androidMuxed = androidStreamingData["formats"] as? [[String: Any]] ?? []
            let androidAdaptive = androidStreamingData["adaptiveFormats"] as? [[String: Any]] ?? []
            let existingItags = Set(formats.compactMap { $0.itag })
            for format in Self.parseFormats(androidMuxed) + Self.parseFormats(androidAdaptive, isAdaptive: true) {
                if let itag = format.itag {
                    if !existingItags.contains(itag) {
                        formats.append(format)
                    }
                } else {
                    formats.append(format)
                }
            }
        }

        let nextJSON = try? await call(endpoint: "next", body: ["videoId": id])
        let related = nextJSON.map { Self.collectVideos(in: $0).filter { $0.id != id } } ?? []

        return (stream, formats, related)
    }

    func channel(id: String) async throws -> (channel: ChannelItem, videos: [StreamItem]) {
        let json = try await call(endpoint: "browse", body: [
            "browseId": id,
            "params": Self.videosTabParams
        ])
        let videos = Self.collectVideos(in: json)
        var name = id
        var subscribers: String?
        var avatar: URL?
        if let metadata = json["metadata"] as? [String: Any],
           let channelMetadata = metadata["channelMetadataRenderer"] as? [String: Any] {
            name = channelMetadata["title"] as? String ?? name
            if let av = channelMetadata["avatar"] as? [String: Any] {
                avatar = (av["url"] as? String).flatMap(URL.init(string:))
            }
        }
        if let header = json["header"] as? [String: Any] {
            for key in ["c4TabbedHeaderRenderer", "pageHeaderRenderer"] {
                if let h = header[key] as? [String: Any] {
                    if let s = h["subscriberCountText"] as? [String: Any], let t = s["simpleText"] as? String {
                        subscribers = t
                    }
                    if let av = h["avatar"] as? [String: Any],
                       let thumbs = av["thumbnails"] as? [[String: Any]],
                       let u = thumbs.last?["url"] as? String {
                        avatar = avatar ?? URL(string: u)
                    }
                }
            }
        }
        let channel = ChannelItem(
            id: id,
            name: name,
            handle: nil,
            avatarURL: avatar,
            subscriberText: subscribers,
            descriptionText: "",
            videoCountText: videos.isEmpty ? nil : "\(videos.count)"
        )
        return (channel, videos)
    }

    func resolveChannelID(fromHandle handle: String) async throws -> String {
        let cleaned = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        guard let url = URL(string: "https://www.youtube.com/@\(cleaned)") else {
            throw ExtractionError.parsingFailed("bad handle")
        }
        let data = try await get(url: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw ExtractionError.parsingFailed("not text")
        }
        let pattern = "UC[A-Za-z0-9_-]{22}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range, in: html) else {
            throw ExtractionError.parsingFailed("no channel id found")
        }
        return String(html[range])
    }
}

extension InnerTubeClient {

    static func runsText(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let runs = dict["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        if let simple = dict["simpleText"] as? String, !simple.isEmpty { return simple }
        if let content = dict["content"] as? String, !content.isEmpty { return content }
        return nil
    }

    private static func parseFormats(_ list: [[String: Any]], isAdaptive: Bool = false) -> [VideoFormat] {
        var formats: [VideoFormat] = []
        for f in list {
            guard let urlString = f["url"] as? String, let url = URL(string: urlString),
                  let mime = f["mimeType"] as? String else { continue }
            let isAudio = mime.hasPrefix("audio/")
            let itag = f["itag"] as? Int
            let height = f["height"] as? Int
            let width = f["width"] as? Int
            let contentLength = (f["contentLength"] as? String).flatMap(Int64.init)
            let kind: VideoFormat.Kind = isAdaptive ? (isAudio ? .audioOnly : .videoOnly) : .muxed
            formats.append(VideoFormat(
                kind: kind,
                url: url,
                itag: itag,
                label: Self.formatLabel(mime: mime, itag: itag, height: height),
                height: height,
                width: width,
                contentLength: contentLength
            ))
        }
        return formats
    }

    static func formatLabel(mime: String, itag: Int?, height: Int?) -> String {
        var parts: [String] = []
        if let height { parts.append("\(height)p") }
        if mime.hasPrefix("audio/") { parts.append("audio") }
        if mime.contains("webm") { parts.append("webm") } else if mime.contains("mp4") { parts.append("mp4") }
        if let itag { parts.append("itag \(itag)") }
        return parts.isEmpty ? mime : parts.joined(separator: " · ")
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func collectVideos(in json: [String: Any]) -> [StreamItem] {
        var items: [StreamItem] = []
        var seen = Set<String>()
        walk(json) { dict in
            if let vr = dict["videoRenderer"] as? [String: Any], let item = parseVideoRenderer(vr), !seen.contains(item.id) {
                seen.insert(item.id)
                items.append(item)
            } else if let vm = dict["lockupViewModel"] as? [String: Any], let item = parseLockup(vm), !seen.contains(item.id) {
                seen.insert(item.id)
                items.append(item)
            }
        }
        return items
    }

    static func collectChannels(in json: [String: Any]) -> [ChannelItem] {
        var items: [ChannelItem] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard let cr = dict["channelRenderer"] as? [String: Any],
                  let id = cr["channelId"] as? String else { return }
            guard !seen.contains(id) else { return }
            seen.insert(id)
            let name = runsText(cr["title"]) ?? id
            var avatar: URL?
            if let av = cr["thumbnail"] as? [String: Any],
               let thumbs = av["thumbnails"] as? [[String: Any]],
               let u = thumbs.last?["url"] as? String {
                avatar = URL(string: u.hasPrefix("//") ? "https:" + u : u)
            }
            let subs = runsText(cr["subscriberCountText"])
            let videos = runsText(cr["videoCountText"])
            items.append(ChannelItem(id: id, name: name, handle: nil, avatarURL: avatar, subscriberText: subs, videoCountText: videos))
        }
        return items
    }

    static func collectPlaylists(in json: [String: Any]) -> [PlaylistItem] {
        var items: [PlaylistItem] = []
        var seen = Set<String>()
        walk(json) { dict in
            guard let pr = dict["playlistRenderer"] as? [String: Any],
                  let id = pr["playlistId"] as? String else { return }
            guard !seen.contains(id) else { return }
            seen.insert(id)
            let title = runsText(pr["title"]) ?? "Playlist"
            var thumb: URL?
            if let thumbs = pr["thumbnails"] as? [[String: Any]],
               let u = thumbs.last?["url"] as? String {
                thumb = URL(string: u.hasPrefix("//") ? "https:" + u : u)
            }
            let owner = runsText(pr["ownerText"]) ?? ""
            let count = pr["videoCount"] as? String
            items.append(PlaylistItem(id: id, title: title, author: owner, thumbnailURL: thumb, videoCountText: count.map { "\($0) videos" }))
        }
        return items
    }

    static func parseVideoRenderer(_ vr: [String: Any]) -> StreamItem? {
        guard let id = vr["videoId"] as? String else { return nil }
        let title = runsText(vr["title"]) ?? "Untitled"
        let author = runsText(vr["ownerText"]) ?? runsText(vr["longBylineText"]) ?? ""
        var authorId: String?
        if let owner = vr["ownerText"] as? [String: Any],
           let runs = owner["runs"] as? [[String: Any]],
           let nav = runs.first?["navigationEndpoint"] as? [String: Any],
           let browse = nav["browseEndpoint"] as? [String: Any] {
            authorId = browse["browseId"] as? String
        }
        var thumb: URL?
        if let thumbs = vr["thumbnail"] as? [String: Any],
           let list = thumbs["thumbnails"] as? [[String: Any]],
           let u = list.last?["url"] as? String {
            thumb = URL(string: u.hasPrefix("//") ? "https:" + u : u)
        }
        let durationText = runsText(vr["lengthText"])
        let views = runsText(vr["shortViewCountText"])
        let published = runsText(vr["publishedTimeText"])
        var desc = ""
        if let snippets = vr["detailedMetadataSnippets"] as? [[String: Any]],
           let first = snippets.first,
           let snippetText = first["snippetText"] as? [String: Any] {
            desc = runsText(snippetText) ?? ""
        }
        return StreamItem(
            id: id,
            title: title,
            author: author,
            authorId: authorId,
            thumbnailURL: thumb ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            durationText: durationText,
            duration: durationText.map(parseDuration),
            viewCountText: views,
            publishedText: published,
            description: desc
        )
    }

    static func parseLockup(_ vm: [String: Any]) -> StreamItem? {
        guard let contentId = vm["contentId"] as? String else { return nil }
        let contentType = vm["contentType"] as? String
        if let contentType, !contentType.contains("VIDEO") { return nil }
        var title: String?
        var author: String?
        var views: String?
        var published: String?
        if let metadata = vm["metadata"] as? [String: Any],
           let metaVM = metadata["lockupMetadataViewModel"] as? [String: Any] {
            title = runsText(metaVM["title"])
            if let meta = metaVM["metadata"] as? [String: Any],
               let content = meta["contentMetadataViewModel"] as? [String: Any],
               let rows = content["metadataRows"] as? [[String: Any]] {
                for row in rows {
                    guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
                    for part in parts {
                        guard let text = runsText(part["text"]) else { continue }
                        if text.contains("view") { views = text }
                        else if text.contains("ago") { published = text }
                        else if author == nil { author = text }
                    }
                }
            }
        }
        var thumb: URL?
        if let cvm = vm["contentImage"] as? [String: Any],
           let thumbVM = cvm["thumbnailViewModel"] as? [String: Any],
           let images = thumbVM["image"] as? [String: Any],
           let sources = images["sources"] as? [[String: Any]],
           let u = sources.last?["url"] as? String {
            thumb = URL(string: u)
        }
        return StreamItem(
            id: contentId,
            title: title ?? "Untitled",
            author: author ?? "",
            authorId: nil,
            thumbnailURL: thumb ?? URL(string: "https://i.ytimg.com/vi/\(contentId)/hqdefault.jpg"),
            durationText: nil,
            duration: nil,
            viewCountText: views,
            publishedText: published,
            description: ""
        )
    }

    static func parseDuration(_ text: String) -> TimeInterval {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private static func walk(_ value: Any, _ visit: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visit(dict)
            for (_, v) in dict { walk(v, visit) }
        } else if let array = value as? [Any] {
            for v in array { walk(v, visit) }
        }
    }
}
