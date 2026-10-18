import Foundation

/// Core domain errors thrown across Yomi subsystems.
public enum YomiError: LocalizedError, Sendable {
    case networkError(String)
    case httpError(statusCode: Int, body: String?)
    case jsonParsingError(String)
    case htmlParsingError(String)
    case sourceNotFound(Int64)
    case cloudflareChallengeRequired(url: URL)
    case decryptionFailed(String)
    case chapterNotFound(String)
    case storageError(String)
    case backupCorrupt(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "Network connection error: \(msg)"
        case .httpError(let code, _): return "HTTP server error: status \(code)"
        case .jsonParsingError(let msg): return "Failed to parse JSON: \(msg)"
        case .htmlParsingError(let msg): return "Failed to parse HTML document: \(msg)"
        case .sourceNotFound(let id): return "Source with ID \(id) not found or not installed."
        case .cloudflareChallengeRequired(let url): return "Cloudflare anti-bot challenge required for \(url.host ?? "source")."
        case .decryptionFailed(let msg): return "Failed to decrypt source assets: \(msg)"
        case .chapterNotFound(let msg): return "Chapter not found: \(msg)"
        case .storageError(let msg): return "Disk storage error: \(msg)"
        case .backupCorrupt(let msg): return "Backup file is corrupt or incompatible: \(msg)"
        case .cancelled: return "Operation cancelled by user."
        }
    }
}

/// Universal protocol implemented by both native connectors (e.g. MangaDex) and JS extensions.
public protocol SourceProtocol: Sendable {
    var manifest: SourceManifest { get }

    func getPopularManga(page: Int) async throws -> MangaPageResult
    func getLatestUpdates(page: Int) async throws -> MangaPageResult
    func searchManga(query: String, filters: [Filter], page: Int) async throws -> MangaPageResult
    func getMangaDetails(manga: Manga) async throws -> Manga
    func getChapterList(manga: Manga) async throws -> [Chapter]
    func getPageList(chapter: Chapter) async throws -> [ReaderPage]
    func getImageData(page: ReaderPage) async throws -> Data
}

/// Metadata describing a remote community extension repository.
public struct ExtensionRepo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { url }
    public var name: String
    public var url: String
    public var websiteUrl: String?
    public var sourcesCount: Int
    public var lastChecked: Date

    public init(
        name: String,
        url: String,
        websiteUrl: String? = nil,
        sourcesCount: Int = 0,
        lastChecked: Date = Date()
    ) {
        self.name = name
        self.url = url
        self.websiteUrl = websiteUrl
        self.sourcesCount = sourcesCount
        self.lastChecked = lastChecked
    }
}
