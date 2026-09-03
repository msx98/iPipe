import Foundation
import Security

enum KeychainStore {
    static let teamID: String = {
        let fromInfo = Bundle.main.object(forInfoDictionaryKey: "TEAM_ID") as? String ?? ""
        let value = fromInfo.hasPrefix("$(") ? "" : fromInfo
        return value.isEmpty ? "A1111ABCDE" : value
    }()
    static let preferredGroup = "\(teamID).ax.lx.ipipe"

    static func save(_ data: Data, service: String) {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(base as CFDictionary)
        var grouped = base
        grouped[kSecAttrAccessGroup as String] = preferredGroup
        let status = SecItemAdd(grouped as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            base.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemDelete(base as CFDictionary)
            SecItemAdd(base as CFDictionary, nil)
        }
    }

    static func load(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            var fallback = query
            fallback[kSecAttrAccessGroup as String] = preferredGroup
            status = SecItemCopyMatching(fallback as CFDictionary, &result)
        }
        return result as? Data
    }

    static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct YTCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var secure: Bool
    var expires: Date?
}

final class CookieStore: @unchecked Sendable {
    static let shared = CookieStore()

    /// Name of the drop file `make install COOKIESFILE=…` delivers into Documents/.
    /// Ingested on startup, then deleted.
    static let dropFileName = "cookies.txt"

    private static let service = "ax.lx.ipipe.ytcookies.v1"
    private static let authNames: Set<String> = [
        "SID", "HSID", "SSID", "APISID", "SAPISID",
        "__Secure-1PSID", "__Secure-3PSID",
        "__Secure-1PSIDTS", "__Secure-3PSIDTS",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        "SIDCC", "LOGIN_INFO", "DELEGATED_SESSION_ID",
        "VISITOR_INFO1_LIVE", "YSC"
    ]
    private static let requiredNames: Set<String> = ["SID", "__Secure-1PSID", "__Secure-3PSID"]

    private let lock = NSLock()
    private var allCookies: [YTCookie]

    private init() {
        if let data = KeychainStore.load(service: Self.service),
           let decoded = try? JSONDecoder().decode([YTCookie].self, from: data) {
            allCookies = decoded
        } else {
            allCookies = []
        }
    }

    var isSignedIn: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return allCookies.contains { Self.requiredNames.contains($0.name) && !$0.value.isEmpty }
    }

    var cookieHeader: String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !allCookies.isEmpty else { return nil }
        return allCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    var sapisid: String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let primary = allCookies.first { $0.name == "SAPISID" }?.value
        let fallback = allCookies.first { $0.name == "__Secure-3PAPISID" }?.value
        return primary ?? fallback
    }

    func replace(_ cookies: [YTCookie]) {
        do {
            self.lock.lock()
            defer { self.lock.unlock() }
            let filtered = Self.authNames.isEmpty ? cookies : cookies.filter { Self.authNames.contains($0.name) }
            allCookies = filtered
        }
        persist()
    }

    func merge(_ cookies: [YTCookie]) {
        do {
            self.lock.lock()
            defer { self.lock.unlock() }
            var byName = Dictionary(uniqueKeysWithValues: allCookies.map { ($0.name, $0) })
            for cookie in cookies where Self.authNames.contains(cookie.name) {
                byName[cookie.name] = cookie
            }
            allCookies = Array(byName.values)
        }
        persist()
    }

    func signOut() {
        self.lock.lock()
        defer { self.lock.unlock() }
        allCookies = []
        KeychainStore.delete(service: Self.service)
    }

    private func persist() {
        let snapshot: [YTCookie]
        do {
            self.lock.lock()
            defer { self.lock.unlock() }
            snapshot = allCookies
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        KeychainStore.save(data, service: Self.service)
    }

    func netscapeExport() -> String {
        let snapshot: [YTCookie]
        do {
            self.lock.lock()
            defer { self.lock.unlock() }
            snapshot = allCookies
        }
        var lines = ["# Netscape HTTP Cookie File", "# Exported by iPipe"]
        for cookie in snapshot {
            let expiry: Int
            if let expires = cookie.expires {
                expiry = Int(expires.timeIntervalSince1970)
            } else {
                expiry = Int(Date().addingTimeInterval(365 * 24 * 3600).timeIntervalSince1970)
            }
            let domain: String
            if cookie.domain.hasPrefix(".") {
                domain = cookie.domain
            } else {
                let stripped = cookie.domain
                    .replacingOccurrences(of: "http://", with: "")
                    .replacingOccurrences(of: "https://", with: "")
                domain = "." + stripped
            }
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let secure = cookie.secure ? "TRUE" : "FALSE"
            let fields = [domain, "TRUE", path, secure, String(expiry), cookie.name, cookie.value]
            lines.append(fields.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    /// Ingests Documents/cookies.txt if present (delivered by the install
    /// pipeline), merges it into the store, and removes the file afterwards —
    /// regardless of the import outcome, so a bad file can't wedge relaunches.
    /// Returns true when the ingest produced signed-in state.
    @discardableResult
    func ingestDroppedFile() -> Bool {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.dropFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("iPipe: failed to read %@", url.path)
            return false
        }
        let ok = importText(text)
        NSLog("iPipe: ingested %@ -> %@", Self.dropFileName, ok ? "signed in" : "no signed-in cookies")
        return ok
    }

    func importText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            if let data = trimmed.data(using: .utf8),
               let cookies = try? JSONDecoder().decode([YTCookie].self, from: data),
               !cookies.isEmpty {
                merge(cookies)
                return isSignedIn
            }
            return false
        }
        var parsed: [YTCookie] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 7, !parts[0].hasPrefix("#") else { continue }
            let expiry = TimeInterval(parts[4]).map { Date(timeIntervalSince1970: $0) }
            let cookie = YTCookie(
                name: parts[5],
                value: parts[6],
                domain: parts[0],
                path: parts[2],
                secure: parts[3].uppercased() == "TRUE",
                expires: expiry
            )
            parsed.append(cookie)
        }
        guard !parsed.isEmpty else { return false }
        merge(parsed)
        return isSignedIn
    }
}
