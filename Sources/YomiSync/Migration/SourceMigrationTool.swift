import Foundation
import YomiCore
import YomiDatabase

public struct MigrationResult: Sendable {
    public let mangaTitle: String
    public let oldSourceId: Int64
    public let newSourceId: Int64
    public let migratedChaptersCount: Int
    public let preservedReadCount: Int

    public init(
        mangaTitle: String,
        oldSourceId: Int64,
        newSourceId: Int64,
        migratedChaptersCount: Int,
        preservedReadCount: Int
    ) {
        self.mangaTitle = mangaTitle
        self.oldSourceId = oldSourceId
        self.newSourceId = newSourceId
        self.migratedChaptersCount = migratedChaptersCount
        self.preservedReadCount = preservedReadCount
    }
}

/// Smart migration engine transferring manga entries to alternative sources while preserving read history.
public final class SourceMigrationTool: Sendable {
    private let mangaRepo: MangaRepository
    private let chapterRepo: ChapterRepository

    public init(
        mangaRepo: MangaRepository = MangaRepository(),
        chapterRepo: ChapterRepository = ChapterRepository()
    ) {
        self.mangaRepo = mangaRepo
        self.chapterRepo = chapterRepo
    }

    /// Migrates a manga to a new target manga found on an alternative source.
    public func migrate(
        manga: Manga,
        toTarget targetManga: Manga,
        targetSource: any SourceProtocol
    ) async throws -> MigrationResult {
        guard let mangaId = manga.id else {
            throw YomiError.storageError("Original manga has no database primary key")
        }

        // 1. Fetch current chapters to preserve read progress
        let oldChapters = try await chapterRepo.getChapters(forMangaId: mangaId)
        let oldChapterMap = Dictionary(grouping: oldChapters, by: { $0.chapterNumber }).compactMapValues { $0.first }

        // 2. Fetch fresh chapter list from the new source
        let newChapters = try await targetSource.getChapterList(manga: targetManga)

        // 3. Reconcile read status, bookmarking, and page progress
        var reconciledChapters: [Chapter] = []
        var preservedRead = 0

        for fresh in newChapters {
            var updated = fresh
            updated.mangaId = mangaId

            if let old = oldChapterMap[fresh.chapterNumber] {
                updated.read = old.read
                updated.bookmark = old.bookmark
                updated.lastPageRead = old.lastPageRead
                if old.read { preservedRead += 1 }
            }
            reconciledChapters.append(updated)
        }

        // 4. Update Manga entity with new sourceId and url
        var updatedManga = manga
        updatedManga.sourceId = targetSource.manifest.id
        updatedManga.url = targetManga.url
        if let newThumb = targetManga.thumbnailUrl, !newThumb.isEmpty {
            updatedManga.thumbnailUrl = newThumb
        }

        try await mangaRepo.upsert(updatedManga)

        // 5. Replace chapters in database
        _ = try await chapterRepo.syncChapters(reconciledChapters, forMangaId: mangaId)

        return MigrationResult(
            mangaTitle: manga.title,
            oldSourceId: manga.sourceId,
            newSourceId: targetSource.manifest.id,
            migratedChaptersCount: reconciledChapters.count,
            preservedReadCount: preservedRead
        )
    }
}
