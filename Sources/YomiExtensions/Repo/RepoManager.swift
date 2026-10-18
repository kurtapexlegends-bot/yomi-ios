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
}

/// Manages fetching, updating, and installing extensions from community repositories.
public final class RepoManager: Sendable {
    public static let shared = RepoManager()

    public init() {}

    /// Fetches and parses a community repository's index.json file.
    public func fetchRepoIndex(from repoUrlString: String) async throws -> RemoteRepoIndex {
        var normalized = repoUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasSuffix("/index.json") && !normalized.hasSuffix(".json") {
            if normalized.hasSuffix("/") {
                normalized += "index.json"
            } else {
                normalized += "/index.json"
            }
        }

        guard let url = URL(string: normalized) else {
            throw YomiError.networkError("Invalid repository URL: \(repoUrlString)")
        }

        var request = URLRequest(url: url)
        request.setValue(NetworkBridge.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw YomiError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: nil)
        }

        do {
            return try JSONDecoder().decode(RemoteRepoIndex.self, from: data)
        } catch {
            throw YomiError.jsonParsingError("Failed to decode repository index: \(error.localizedDescription)")
        }
    }

    /// Downloads and installs a remote extension script into the local sandbox.
    public func installExtension(package: RemoteExtensionPackage) async throws -> String {
        guard let url = URL(string: package.scriptUrl) else {
            throw YomiError.networkError("Invalid script URL: \(package.scriptUrl)")
        }

        var request = URLRequest(url: url)
        request.setValue(NetworkBridge.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        let fileManager = FileManager.default
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let extDir = appSupport.appendingPathComponent("Yomi/extensions", isDirectory: true)
        if !fileManager.fileExists(atPath: extDir.path) {
            try fileManager.createDirectory(at: extDir, withIntermediateDirectories: true)
        }

        let targetScriptURL = extDir.appendingPathComponent("\(package.id).js")
        try data.write(to: targetScriptURL)

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
}
