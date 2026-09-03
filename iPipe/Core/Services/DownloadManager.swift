import Foundation
import Observation

enum DownloadKind: String, Codable {
    case video
    case audio
}

enum DownloadState: String, Codable {
    case downloading
    case done
    case failed
}

struct DownloadItem: Codable, Identifiable {
    var id: String
    var videoId: String
    var title: String
    var author: String
    var kind: DownloadKind
    var videoPath: String?
    var audioPath: String?
    var progress: Double
    var state: DownloadState
    var totalBytes: Int64
    var duration: TimeInterval?
    var createdAt: Date
}

final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: (String, Double, Int64) -> Void = { _, _, _ in }
    var onFinish: (String, URL) -> Void = { _, _ in }
    var onError: (String, Error) -> Void = { _, _ in }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let description = downloadTask.taskDescription else { return }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            let failedDescription = description
            Task { @MainActor in onError(failedDescription, error) }
            return
        }
        let finishedDescription = description
        let finishedURL = staging
        Task { @MainActor in onFinish(finishedDescription, finishedURL) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription else { return }
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let progressDescription = description
        Task { @MainActor in onProgress(progressDescription, fraction, totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let description = task.taskDescription else { return }
        let errorDescription = description
        let errorValue = error
        Task { @MainActor in onError(errorDescription, errorValue) }
    }
}

@Observable
@MainActor
final class DownloadManager: NSObject {
    var items: [DownloadItem] = []
    let directory: URL

    private let session: URLSession
    private let delegate = DownloadSessionDelegate()
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var expectedParts: [String: Set<String>] = [:]
    private static let storageKey = "np.downloads.v1"

    override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        super.init()
        delegate.onProgress = { [weak self] description, fraction, bytes in
            Task { @MainActor in self?.handleProgress(description: description, fraction: fraction) }
        }
        delegate.onFinish = { [weak self] description, location in
            Task { @MainActor in self?.handleFinish(description: description, location: location) }
        }
        delegate.onError = { [weak self] description, error in
            Task { @MainActor in self?.handleError(description: description, error: error) }
        }
        load()
    }

    func startDownload(stream: StreamItem, formats: [VideoFormat], kind: DownloadKind) {
        let id = "\(stream.id)|\(kind.rawValue)"
        if let existing = items.first(where: { $0.id == id }) {
            guard existing.state == .failed else { return }
            remove(existing)
        }

        let audioCandidates = formats.filter { $0.kind == .audioOnly && $0.label.contains("mp4") }
        let audioPick: VideoFormat?
        if let preferred = audioCandidates.first(where: { $0.itag == 140 }) {
            audioPick = preferred
        } else {
            audioPick = formats.first { $0.kind == .audioOnly }
        }

        let videoCandidates = formats.filter { $0.kind == .videoOnly && $0.label.contains("mp4") }
        let capped = videoCandidates.filter { ($0.height ?? 0) <= 1080 }
        let videoPick: VideoFormat?
        if let best = capped.max(by: { ($0.height ?? 0) < ($1.height ?? 0) }) {
            videoPick = best
        } else if let best = videoCandidates.max(by: { ($0.height ?? 0) < ($1.height ?? 0) }) {
            videoPick = best
        } else {
            let muxed22 = formats.first { $0.kind == .muxed && $0.itag == 22 }
            let muxed18 = formats.first { $0.kind == .muxed && $0.itag == 18 }
            videoPick = muxed22 ?? muxed18
        }

        var parts: [(part: String, format: VideoFormat)] = []
        switch kind {
        case .audio:
            guard let audio = audioPick else { return }
            parts = [("audio", audio)]
        case .video:
            guard let video = videoPick else { return }
            parts = [("video", video)]
            if video.kind == .videoOnly, let audio = audioPick {
                parts.append(("audio", audio))
            }
        }
        guard !parts.isEmpty else { return }

        let item = DownloadItem(
            id: id,
            videoId: stream.id,
            title: stream.title,
            author: stream.author,
            kind: kind,
            videoPath: nil,
            audioPath: nil,
            progress: 0,
            state: .downloading,
            totalBytes: parts.reduce(Int64(0)) { $0 + ($1.format.contentLength ?? 0) },
            duration: stream.duration,
            createdAt: Date()
        )
        items.append(item)
        expectedParts[id] = Set(parts.map { $0.part })
        save()
        for element in parts {
            let description = "\(id)|\(element.part)"
            let task = session.downloadTask(with: element.format.url)
            task.taskDescription = description
            tasks[description] = task
            task.resume()
        }
    }

    func item(for videoId: String, kind: DownloadKind) -> DownloadItem? {
        items.first { $0.videoId == videoId && $0.kind == kind }
    }

    func remove(_ item: DownloadItem) {
        let descriptions = tasks.keys.filter { $0.hasPrefix("\(item.id)|") }
        for description in descriptions {
            tasks[description]?.cancel()
            tasks.removeValue(forKey: description)
        }
        if let videoPath = item.videoPath {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(videoPath))
        }
        if let audioPath = item.audioPath {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(audioPath))
        }
        items.removeAll { $0.id == item.id }
        expectedParts.removeValue(forKey: item.id)
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            items = decoded
        }
        for index in items.indices where items[index].state == .downloading {
            items[index].state = .failed
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func parseDescription(_ description: String) -> (id: String, part: String)? {
        guard let range = description.range(of: "|", options: .backwards) else { return nil }
        let id = String(description[..<range.lowerBound])
        let part = String(description[range.upperBound...])
        guard !id.isEmpty, !part.isEmpty else { return nil }
        return (id, part)
    }

    private func requiredParts(for item: DownloadItem) -> Set<String> {
        switch item.kind {
        case .audio: return ["audio"]
        case .video:
            if item.audioPath != nil { return ["video", "audio"] }
            return ["video"]
        }
    }

    private func handleProgress(description: String, fraction: Double) {
        guard let parsed = parseDescription(description),
              let index = items.firstIndex(where: { $0.id == parsed.id && $0.state == .downloading }) else { return }
        items[index].progress = min(max(fraction, 0), 1)
        save()
    }

    private func handleFinish(description: String, location: URL) {
        guard let parsed = parseDescription(description) else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        guard let index = items.firstIndex(where: { $0.id == parsed.id }) else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        let item = items[index]
        let fileExtension = parsed.part == "video" ? "mp4" : "m4a"
        let fileName = "\(item.videoId).\(item.kind.rawValue).\(parsed.part).\(fileExtension)"
        let destination = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            items[index].state = .failed
            tasks.removeValue(forKey: description)
            save()
            return
        }
        if parsed.part == "video" {
            items[index].videoPath = fileName
        } else {
            items[index].audioPath = fileName
        }
        let required = expectedParts[parsed.id] ?? requiredParts(for: item)
        let hasAllParts = required.allSatisfy { partName in
            partName == "video" ? items[index].videoPath != nil : items[index].audioPath != nil
        }
        if hasAllParts {
            items[index].state = .done
            items[index].progress = 1
            expectedParts.removeValue(forKey: parsed.id)
        }
        tasks.removeValue(forKey: description)
        save()
    }

    private func handleError(description: String, error: Error) {
        guard let parsed = parseDescription(description),
              let index = items.firstIndex(where: { $0.id == parsed.id && $0.state == .downloading }) else { return }
        items[index].state = .failed
        tasks.removeValue(forKey: description)
        save()
    }
}
