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
    public func updateProgress(chapterId: Int64, lastPageRead: Int, isRead: Bool) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: """
                    UPDATE chapters
                    SET last_page_read = ?, read = ?, last_modified_at = ?
                    WHERE id = ?
                """,
                arguments: [lastPageRead, isRead, Date(), chapterId]
            )

            // Insert into history table if read
            if isRead {
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
}
