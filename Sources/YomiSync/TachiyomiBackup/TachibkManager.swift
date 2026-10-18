import Foundation
import YomiCore
import YomiDatabase

/// Handles importing and exporting Tachiyomi / Mihon .tachibk backup archives.
public final class TachibkManager: Sendable {
    public static let shared = TachibkManager()

    private let mangaRepo: MangaRepository
    private let chapterRepo: ChapterRepository
    private let categoryRepo: CategoryRepository
    private let trackRepo: TrackRepository

    public init(
        mangaRepo: MangaRepository = MangaRepository(),
        chapterRepo: ChapterRepository = ChapterRepository(),
        categoryRepo: CategoryRepository = CategoryRepository(),
        trackRepo: TrackRepository = TrackRepository()
    ) {
        self.mangaRepo = mangaRepo
        self.chapterRepo = chapterRepo
        self.categoryRepo = categoryRepo
        self.trackRepo = trackRepo
    }

    /// Restores library manga, chapters, categories, and tracking links from a .tachibk backup file.
    public func restoreBackup(from fileURL: URL) async throws -> (restoredMangas: Int, restoredChapters: Int) {
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let rawData = try Data(contentsOf: fileURL)
        let decompressedData = decompressGZIPIfNeeded(data: rawData)

        let root: TachibkRoot
        do {
            root = try JSONDecoder().decode(TachibkRoot.self, from: decompressedData)
        } catch {
            throw YomiError.backupCorrupt("Failed to parse backup payload: \(error.localizedDescription)")
        }

        var totalMangas = 0
        var totalChapters = 0

        // 1. Restore Categories
        var categoryMap: [Int: Int64] = [:]
        for cat in root.backupCategories {
            let created = try await categoryRepo.createCategory(name: cat.name, isLocked: false)
            if let id = created.id {
                categoryMap[cat.order] = id
            }
        }

        // 2. Restore Mangas and Chapters
        for bManga in root.backupManga {
            let manga = Manga(
                sourceId: bManga.source,
                url: bManga.url,
                title: bManga.title,
                author: bManga.author,
                artist: bManga.artist,
                description: bManga.description,
                genres: bManga.genre,
                status: MangaStatus(rawValue: bManga.status) ?? .unknown,
                thumbnailUrl: bManga.thumbnailUrl,
                customThumbnailUrl: bManga.customThumbnailUrl,
                inLibrary: bManga.favorite,
                viewer: MangaViewer(rawValue: bManga.viewer) ?? .defaultViewer,
                chapterFlags: bManga.chapterFlags
            )

            let savedManga = try await mangaRepo.upsert(manga)
            guard let mangaId = savedManga.id else { continue }
            totalMangas += 1

            // Bind categories
            let mappedCatIds = bManga.categories.compactMap { categoryMap[$0] }
            if !mappedCatIds.isEmpty {
                try await categoryRepo.setMangaCategories(mangaId: mangaId, categoryIds: mappedCatIds)
            }

            // Restore Chapters
            let chapters: [Chapter] = bManga.chapters.map { bCh in
                Chapter(
                    mangaId: mangaId,
                    url: bCh.url,
                    name: bCh.name,
                    scanlator: bCh.scanlator,
                    read: bCh.read,
                    bookmark: bCh.bookmark,
                    lastPageRead: bCh.lastPageRead,
                    chapterNumber: bCh.chapterNumber,
                    sourceOrder: bCh.sourceOrder,
                    dateFetch: Date(timeIntervalSince1970: Double(bCh.dateFetch) / 1000.0),
                    dateUpload: Date(timeIntervalSince1970: Double(bCh.dateUpload) / 1000.0)
                )
            }
            _ = try await chapterRepo.syncChapters(chapters, forMangaId: mangaId)
            totalChapters += chapters.count

            // Restore Trackers
            for bTrack in bManga.tracking {
                let track = Track(
                    mangaId: mangaId,
                    syncId: bTrack.syncId,
                    remoteId: bTrack.mediaIdInt,
                    libraryId: bTrack.libraryId,
                    title: bTrack.title,
                    lastChapterRead: bTrack.lastChapterRead,
                    totalChapters: bTrack.totalChapters,
                    score: Double(bTrack.score),
                    status: TrackStatus(rawValue: bTrack.status) ?? .reading,
                    trackingUrl: bTrack.trackingUrl
                )
                try await trackRepo.upsertTrack(track)
            }
        }

        return (totalMangas, totalChapters)
    }

    /// Exports current library, categories, and tracking metadata into a .tachibk backup file.
    public func exportBackup(to destinationURL: URL) async throws {
        let libraryMangas = try await mangaRepo.getLibraryMangas()
        let categories = try await categoryRepo.getAllCategories()

        var backupMangas: [BackupManga] = []

        for manga in libraryMangas {
            guard let mId = manga.id else { continue }
            let chapters = try await chapterRepo.getChapters(forMangaId: mId)
            let tracks = try await trackRepo.getTracks(forMangaId: mId)
            let catIds = try await categoryRepo.getCategoryIds(forMangaId: mId)

            let bChapters = chapters.map { ch in
                BackupChapter(
                    url: ch.url,
                    name: ch.name,
                    scanlator: ch.scanlator,
                    read: ch.read,
                    bookmark: ch.bookmark,
                    lastPageRead: ch.lastPageRead,
                    dateFetch: Int64(ch.dateFetch.timeIntervalSince1970 * 1000),
                    dateUpload: Int64(ch.dateUpload.timeIntervalSince1970 * 1000),
                    chapterNumber: ch.chapterNumber,
                    sourceOrder: ch.sourceOrder
                )
            }

            let bTracks = tracks.map { tr in
                BackupTracking(
                    syncId: tr.syncId,
                    libraryId: tr.libraryId,
                    mediaIdInt: tr.remoteId,
                    trackingUrl: tr.trackingUrl,
                    title: tr.title,
                    lastChapterRead: tr.lastChapterRead,
                    totalChapters: tr.totalChapters,
                    score: Float(tr.score),
                    status: tr.status.rawValue
                )
            }

            let bManga = BackupManga(
                source: manga.sourceId,
                url: manga.url,
                title: manga.title,
                artist: manga.artist,
                author: manga.author,
                description: manga.description,
                genre: manga.genres,
                status: manga.status.rawValue,
                thumbnailUrl: manga.thumbnailUrl,
                customThumbnailUrl: manga.customThumbnailUrl,
                favorite: manga.inLibrary,
                viewer: manga.viewer.rawValue,
                chapterFlags: manga.chapterFlags,
                chapters: bChapters,
                categories: catIds.map { Int($0) },
                tracking: bTracks
            )
            backupMangas.append(bManga)
        }

        let bCategories = categories.map { cat in
            BackupCategory(name: cat.name, order: cat.order, flags: cat.flags)
        }

        let root = TachibkRoot(backupManga: backupMangas, backupCategories: bCategories, backupSources: [])
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        let jsonData = try jsonEncoder.encode(root)

        // Compress or write directly to target URL
        try jsonData.write(to: destinationURL)
    }

    private func decompressGZIPIfNeeded(data: Data) -> Data {
        // Detect GZIP header magic bytes (0x1f, 0x8b)
        guard data.count > 2, data[0] == 0x1f, data[1] == 0x8b else {
            return data
        }
        // If compressed, decode payload via NSData decompression
        if let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data {
            return decompressed
        }
        return data
    }
}
