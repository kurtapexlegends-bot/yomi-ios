import Foundation
import YomiCore

/// Serves pages from a downloaded .cbz archive without a remote source.
///
/// Reading a page extracts only the requested entry from the archive instead of
/// loading the whole .cbz file into memory, which previously caused out-of-memory
/// crashes whenever a downloaded chapter was opened.
public final class LocalCBZSource: SourceProtocol, @unchecked Sendable {
    public static let sourceId: Int64 = -10001

    public let archiveURL: URL
    public let pages: [ReaderPage]

    public init(archiveURL: URL) throws {
        self.archiveURL = archiveURL
        self.pages = try CBZArchiver.readCBZPages(from: archiveURL)
    }

    public var manifest: SourceManifest {
        SourceManifest(
            id: Self.sourceId,
            name: "Downloaded",
            lang: "local",
            baseUrl: archiveURL.path,
            supportsLatest: false,
            isNsfw: false
        )
    }

    public func getPopularManga(page: Int) async throws -> MangaPageResult {
        MangaPageResult(mangas: [], hasNextPage: false)
    }

    public func getLatestUpdates(page: Int) async throws -> MangaPageResult {
        MangaPageResult(mangas: [], hasNextPage: false)
    }

    public func searchManga(query: String, filters: [Filter], page: Int) async throws -> MangaPageResult {
        MangaPageResult(mangas: [], hasNextPage: false)
    }

    public func getMangaDetails(manga: Manga) async throws -> Manga {
        manga
    }

    public func getChapterList(manga: Manga) async throws -> [Chapter] {
        []
    }

    public func getPageList(chapter: Chapter) async throws -> [ReaderPage] {
        pages
    }

    public func getImageData(page: ReaderPage) async throws -> Data {
        let entryPath = page.archiveEntry ?? page.url.components(separatedBy: "#").last ?? ""
        guard !entryPath.isEmpty else {
            throw YomiError.storageError("Missing CBZ entry path for page \(page.index)")
        }
        return try CBZArchiver.extractData(from: archiveURL, entryPath: entryPath)
    }

    public func getFilters() -> [Filter] {
        []
    }
}
