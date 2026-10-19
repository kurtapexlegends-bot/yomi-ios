import Foundation
import GRDB
import YomiCore

public final class ChapterRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches all chapters for a manga sorted by chapter number descending.
    public func getChapters(forMangaId mangaId: Int64) async throws -> [Chapter] {
        try await dbManager.read { db in
            try ChapterRecord
                .filter(Column("manga_id") == mangaId)
                .order(Column("chapter_number").desc, Column("source_order").asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Fetches a specific chapter by primary key.
    public func getChapter(id: Int64) async throws -> Chapter? {
        try await dbManager.read { db in
            try ChapterRecord.fetchOne(db, key: id)?.toDomain()
        }
    }

    /// Synchronizes a fresh chapter list from a source into the database, preserving user read/bookmark flags.
    public func syncChapters(_ freshChapters: [Chapter], forMangaId mangaId: Int64) async throws -> [Chapter] {
        try await dbManager.write { db in
            // Fetch existing chapters to preserve user status
            let existingList = try ChapterRecord
                .filter(Column("manga_id") == mangaId)
                .fetchAll(db)
            let existingMap = Dictionary(grouping: existingList, by: { $0.url }).compactMapValues { $0.first }

            var updatedDomainChapters: [Chapter] = []

            for chapter in freshChapters {
                var record = ChapterRecord(chapter: chapter)
                record.manga_id = mangaId

                if let existing = existingMap[chapter.url] {
                    record.id = existing.id
                    record.read = existing.read
                    record.bookmark = existing.bookmark
                    record.last_page_read = existing.last_page_read
                    try record.update(db)
                } else {
                    try record.insert(db)
                }
                updatedDomainChapters.append(record.toDomain())
            }

            return updatedDomainChapters
        }
    }

    /// Updates reading progress for a chapter and logs to history if not incognito.
    public func updateProgress(chapterId: Int64, lastPageRead: Int, isRead: Bool, logHistory: Bool = true) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: """
                    UPDATE chapters
                    SET last_page_read = ?, read = ?, last_modified_at = ?
                    WHERE id = ?
                """,
                arguments: [lastPageRead, isRead, Date(), chapterId]
            )

            if logHistory {
                // Deduplicate and insert latest reading history entry
                try db.execute(
                    sql: "DELETE FROM history WHERE chapter_id = ?",
                    arguments: [chapterId]
                )
                try db.execute(
                    sql: "INSERT INTO history(chapter_id, read_at) VALUES (?, ?)",
                    arguments: [chapterId, Date()]
                )
            }
        }
    }

    /// Marks all previous chapters prior to a specific chapter number as read.
    public func markPreviousChaptersRead(mangaId: Int64, beforeChapterNumber: Float) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: """
                    UPDATE chapters
                    SET read = 1, last_modified_at = ?
                    WHERE manga_id = ? AND chapter_number < ? AND chapter_number >= 0
                """,
                arguments: [Date(), mangaId, Double(beforeChapterNumber)]
            )
        }
    }

    /// Toggles chapter bookmark flag.
    public func setBookmark(chapterId: Int64, isBookmarked: Bool) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE chapters SET bookmark = ?, last_modified_at = ? WHERE id = ?",
                arguments: [isBookmarked, Date(), chapterId]
            )
        }
    }

    /// Counts unread chapters for a manga.
    public func getUnreadCount(forMangaId mangaId: Int64) async throws -> Int {
        try await dbManager.read { db in
            try ChapterRecord
                .filter(Column("manga_id") == mangaId && Column("read") == false)
                .fetchCount(db)
        }
    }

    /// Returns recently fetched or uploaded chapters for manga in the user's library.
    public func getRecentUpdates(limit: Int = 100) async throws -> [ChapterUpdateItem] {
        try await dbManager.read { db in
            let sql = """
                SELECT
                    c.id AS chapter_id,
                    c.manga_id,
                    c.name AS chapter_name,
                    c.chapter_number,
                    c.date_upload,
                    c.date_fetch,
                    c.read AS chapter_read,
                    c.bookmark AS chapter_bookmark,
                    c.last_page_read,
                    c.url AS chapter_url,
                    m.title AS manga_title,
                    m.thumbnail_url,
                    m.custom_thumbnail_url,
                    m.source_id,
                    m.url AS manga_url
                FROM chapters c
                INNER JOIN mangas m ON m.id = c.manga_id
                WHERE m.in_library = 1
                ORDER BY c.date_fetch DESC, c.date_upload DESC, c.id DESC
                LIMIT ?
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
            return rows.map { row in
                ChapterUpdateItem(
                    chapterId: row["chapter_id"],
                    mangaId: row["manga_id"],
                    mangaTitle: row["manga_title"],
                    chapterName: row["chapter_name"],
                    chapterNumber: Float(row["chapter_number"] as Double? ?? -1.0),
                    dateUpload: row["date_upload"],
                    dateFetch: row["date_fetch"],
                    read: row["chapter_read"],
                    bookmark: row["chapter_bookmark"],
                    lastPageRead: row["last_page_read"],
                    thumbnailUrl: row["thumbnail_url"],
                    customThumbnailUrl: row["custom_thumbnail_url"],
                    sourceId: row["source_id"],
                    mangaUrl: row["manga_url"],
                    chapterUrl: row["chapter_url"]
                )
            }
        }
    }
}

/// Domain representation of a recently released or fetched chapter for manga in the library.
public struct ChapterUpdateItem: Identifiable, Sendable {
    public var id: Int64 { chapterId }
    public var chapterId: Int64
    public var mangaId: Int64
    public var mangaTitle: String
    public var chapterName: String
    public var chapterNumber: Float
    public var dateUpload: Date
    public var dateFetch: Date
    public var read: Bool
    public var bookmark: Bool
    public var lastPageRead: Int
    public var thumbnailUrl: String?
    public var customThumbnailUrl: String?
    public var sourceId: Int64
    public var mangaUrl: String
    public var chapterUrl: String

    public init(
        chapterId: Int64,
        mangaId: Int64,
        mangaTitle: String,
        chapterName: String,
        chapterNumber: Float,
        dateUpload: Date,
        dateFetch: Date,
        read: Bool,
        bookmark: Bool,
        lastPageRead: Int,
        thumbnailUrl: String? = nil,
        customThumbnailUrl: String? = nil,
        sourceId: Int64,
        mangaUrl: String,
        chapterUrl: String
    ) {
        self.chapterId = chapterId
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.chapterName = chapterName
        self.chapterNumber = chapterNumber
        self.dateUpload = dateUpload
        self.dateFetch = dateFetch
        self.read = read
        self.bookmark = bookmark
        self.lastPageRead = lastPageRead
        self.thumbnailUrl = thumbnailUrl
        self.customThumbnailUrl = customThumbnailUrl
        self.sourceId = sourceId
        self.mangaUrl = mangaUrl
        self.chapterUrl = chapterUrl
    }

    public var effectiveThumbnailUrl: String? {
        customThumbnailUrl ?? thumbnailUrl
    }

    /// Formatted chapter display title.
    public var displayChapterTitle: String {
        if chapterNumber >= 0 {
            let formattedNumber = chapterNumber.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", chapterNumber)
                : String(format: "%.1f", chapterNumber)
            let trimmedName = chapterName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                return "Ch. \(formattedNumber)"
            }
            if trimmedName.lowercased().hasPrefix("chapter") || trimmedName.lowercased().hasPrefix("ch.") {
                return trimmedName
            }
            return "Ch. \(formattedNumber) — \(trimmedName)"
        }
        return chapterName.isEmpty ? "Chapter" : chapterName
    }
}
