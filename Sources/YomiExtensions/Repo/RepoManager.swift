import Foundation
import YomiCore

/// Remote repository manifest representing an extension package available for download.
public struct RemoteExtensionPackage: Identifiable, Codable, Sendable {
    public var id: Int64
    public var name: String
    public var lang: String
    public var baseUrl: String
    public var iconUrl: String?
    public var version: String
    public var scriptUrl: String
    public var isNsfw: Bool

    public init(
        id: Int64,
        name: String,
        lang: String = "en",
        baseUrl: String,
        iconUrl: String? = nil,
        version: String = "1.0.0",
        scriptUrl: String,
        isNsfw: Bool = false
    ) {
        self.id = id
        self.name = name
        self.lang = lang
        self.baseUrl = baseUrl
        self.iconUrl = iconUrl
        self.version = version
        self.scriptUrl = scriptUrl
        self.isNsfw = isNsfw
    }
}

/// Remote community repository JSON index payload.
public struct RemoteRepoIndex: Codable, Sendable {
    public let name: String
    public let website: String?
    public let extensions: [RemoteExtensionPackage]

    public init(name: String, website: String? = nil, extensions: [RemoteExtensionPackage]) {
        self.name = name
        self.website = website
        self.extensions = extensions
    }
}

/// Manages fetching, updating, and installing extensions from community repositories.
public final class RepoManager: @unchecked Sendable {
    public static let shared = RepoManager()

    /// Standard official and recommended repository URLs
    public static let keiyoushiRepoURL = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json"

    private let cacheLock = NSLock()
    private var indexCache: [String: (index: RemoteRepoIndex, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes in-memory cache

    public init() {}

    /// Normalizes repository URLs, auto-mapping GitHub links and legacy index.min.json to modern index.json
    public func normalizeRepoUrl(_ rawUrl: String) -> String {
        var trimmed = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("<") || trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            trimmed.removeFirst()
        }
        while trimmed.hasSuffix(">") || trimmed.hasSuffix("\"") || trimmed.hasSuffix("'") || trimmed.hasSuffix(".") || trimmed.hasSuffix(",") || trimmed.hasSuffix(";") {
            trimmed.removeLast()
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)

        // Any URL containing keiyoushi maps directly to modern official index
        if trimmed.lowercased().contains("keiyoushi") {
            return Self.keiyoushiRepoURL
        }

        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }

        if trimmed.contains("index.min.json") {
            trimmed = trimmed.replacingOccurrences(of: "index.min.json", with: "index.json")
        }

        if !trimmed.hasSuffix(".json") {
            if trimmed.hasSuffix("/") {
                trimmed += "index.json"
            } else {
                trimmed += "/index.json"
            }
        }

        return trimmed
    }

    /// Fetches and parses a community repository's index (supporting Yomi, Keiyoushi v2, and legacy formats).
    public func fetchRepoIndex(from repoUrlString: String, forceRefresh: Bool = false) async throws -> RemoteRepoIndex {
        let normalized = normalizeRepoUrl(repoUrlString)

        if !forceRefresh {
            cacheLock.lock()
            if let cached = indexCache[normalized], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
                cacheLock.unlock()
                return cached.index
            }
            cacheLock.unlock()
        }

        guard let url = URL(string: normalized) else {
            throw YomiError.networkError("Invalid repository URL: \(repoUrlString)")
        }

        var request = URLRequest(url: url)
        request.setValue(NetworkBridge.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw YomiError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: nil)
        }

        do {
            let parsed = try parseRepoData(data, sourceUrl: normalized)
            cacheLock.lock()
            indexCache[normalized] = (parsed, Date())
            cacheLock.unlock()
            return parsed
        } catch let YomiError.jsonParsingError(msg) where msg == "deprecated_stub" {
            // Self-healing fallback: seamlessly fetch Keiyoushi modern v2 index
            return try await fetchRepoIndex(from: Self.keiyoushiRepoURL, forceRefresh: true)
        }
    }

    /// Flexible multi-schema parser handling Yomi, Keiyoushi v2 (`extensionList.extensions`), and legacy array formats.
    public func parseRepoData(_ data: Data, sourceUrl: String) throws -> RemoteRepoIndex {
        // 1. Try standard Yomi schema
        if let directIndex = try? JSONDecoder().decode(RemoteRepoIndex.self, from: data), !directIndex.extensions.isEmpty {
            return directIndex
        }

        // 2. Try generic JSON object (Keiyoushi v2 / Mihon format)
        if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let repoName = jsonDict["name"] as? String ?? "Community Repository"
            let contact = jsonDict["contact"] as? [String: Any]
            let website = contact?["website"] as? String ?? jsonDict["website"] as? String

            var rawList: [[String: Any]] = []
            if let extListObj = jsonDict["extensionList"] as? [String: Any],
               let exts = extListObj["extensions"] as? [[String: Any]] {
                rawList = exts
            } else if let exts = jsonDict["extensions"] as? [[String: Any]] {
                rawList = exts
            }

            if !rawList.isEmpty {
                let packages = parseExtensionPackages(from: rawList)
                return RemoteRepoIndex(name: repoName, website: website, extensions: packages)
            }
        }

        // 3. Try legacy top-level JSON array
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Check if this is the "Outdated App" warning payload from index.min.json
            let isOutdatedStub = jsonArray.contains { dict in
                let name = dict["name"] as? String ?? ""
                return name.localizedCaseInsensitiveContains("Outdated App") || name.localizedCaseInsensitiveContains("Update to Mihon")
            }

            if isOutdatedStub {
                // Signal to fetchRepoIndex to self-heal to modern Keiyoushi v2 index
                throw YomiError.jsonParsingError("deprecated_stub")
            }

            let packages = parseExtensionPackages(from: jsonArray)
            return RemoteRepoIndex(name: "Community Repository", website: nil, extensions: packages)
        }

        throw YomiError.jsonParsingError("Failed to decode repository index. Unrecognized schema.")
    }

    /// Extracts packages from raw JSON dictionaries (supporting nested sources arrays)
    private func parseExtensionPackages(from rawList: [[String: Any]]) -> [RemoteExtensionPackage] {
        var packages: [RemoteExtensionPackage] = []

        for item in rawList {
            let pkgName = item["packageName"] as? String ?? item["pkg"] as? String ?? item["name"] as? String ?? ""
            let displayName = item["name"] as? String ?? pkgName
            guard !displayName.isEmpty else { continue }

            // Skip stub warning packages
            if displayName.localizedCaseInsensitiveContains("Outdated App") || displayName.localizedCaseInsensitiveContains("Update to Mihon") {
                continue
            }

            let versionName = item["versionName"] as? String ?? item["version"] as? String ?? "1.0.0"
            let warning = item["contentWarning"] as? String ?? ""
            let isNsfw = warning.contains("NSFW") || (item["nsfw"] as? Int == 1)

            let resources = item["resources"] as? [String: Any]
            let iconUrl = resources?["iconUrl"] as? String ?? item["iconUrl"] as? String
            let scriptUrl = resources?["apkUrl"] as? String ?? resources?["jarUrl"] as? String ?? item["scriptUrl"] as? String ?? ""

            // Handle nested sources array inside the extension
            if let sources = item["sources"] as? [[String: Any]], !sources.isEmpty {
                for s in sources {
                    let sName = s["name"] as? String ?? displayName
                    let sLang = s["language"] as? String ?? s["lang"] as? String ?? item["lang"] as? String ?? "en"
                    let sBase = s["homeUrl"] as? String ?? s["baseUrl"] as? String ?? ""
                    let sIdStr = s["id"] as? String ?? ""
                    let sId: Int64
                    if let direct = Int64(sIdStr) {
                        sId = direct
                    } else if let unsigned = UInt64(sIdStr) {
                        sId = Int64(bitPattern: unsigned)
                    } else {
                        sId = Int64(abs((pkgName + sLang + sName).hashValue))
                    }

                    packages.append(RemoteExtensionPackage(
                        id: sId,
                        name: sName,
                        lang: sLang,
                        baseUrl: sBase,
                        iconUrl: iconUrl,
                        version: versionName,
                        scriptUrl: scriptUrl,
                        isNsfw: isNsfw
                    ))
                }
            } else {
                let lang = item["lang"] as? String ?? "en"
                let id = abs(Int64(pkgName.hashValue))
                packages.append(RemoteExtensionPackage(
                    id: id,
                    name: displayName,
                    lang: lang,
                    baseUrl: item["baseUrl"] as? String ?? "",
                    iconUrl: iconUrl,
                    version: versionName,
                    scriptUrl: scriptUrl,
                    isNsfw: isNsfw
                ))
            }
        }

        // Deduplicate packages by ID to guarantee SwiftUI identity integrity
        var seenIds = Set<Int64>()
        return packages.filter { pkg in
            if seenIds.contains(pkg.id) {
                return false
            }
            seenIds.insert(pkg.id)
            return true
        }
    }

    /// Downloads and installs a remote extension script into the local sandbox.
    public func installExtension(package: RemoteExtensionPackage) async throws -> String {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let extDir = appSupport.appendingPathComponent("Yomi/extensions", isDirectory: true)
        if !fileManager.fileExists(atPath: extDir.path) {
            try fileManager.createDirectory(at: extDir, withIntermediateDirectories: true)
        }

        let targetScriptURL = extDir.appendingPathComponent("\(package.id).js")

        // If package has a downloadable JS script, download it; otherwise generate a sandboxed JS bridge scraper
        if package.scriptUrl.hasSuffix(".js"), let url = URL(string: package.scriptUrl) {
            var request = URLRequest(url: url)
            request.setValue(NetworkBridge.defaultUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            try data.write(to: targetScriptURL)
        } else {
            // Generate compliant JavaScriptCore scraper script for HTML web scraping
            let generatedScript = generateScraperScript(for: package)
            guard let scriptData = generatedScript.data(using: .utf8) else {
                throw YomiError.storageError("Failed to encode scraper script")
            }
            try scriptData.write(to: targetScriptURL)
        }

        // Save manifest metadata
        let manifest = SourceManifest(
            id: package.id,
            name: package.name,
            lang: package.lang,
            baseUrl: package.baseUrl,
            iconUrl: package.iconUrl,
            version: package.version,
            isNsfw: package.isNsfw
        )
        let metaURL = extDir.appendingPathComponent("\(package.id).json")
        let metaData = try JSONEncoder().encode(manifest)
        try metaData.write(to: metaURL)

        return targetScriptURL.path
    }

    /// Generates a compliant JavaScriptCore scraper script for an extension package
    func generateScraperScript(for package: RemoteExtensionPackage) -> String {
        ScraperScriptGenerator.generateScraperScript(for: package)
    }
}
