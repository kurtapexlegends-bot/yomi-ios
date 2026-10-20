import Foundation
import GRDB
import YomiCore

/// Domain representation of a reading history entry joined with chapter and manga information.
public struct HistoryItem: Identifiable, Sendable {
    public var id: Int64
    public var chapterId: Int64
    public var mangaId: Int64
    public var mangaTitle: String
    public var chapterName: String
    public var chapterNumber: Float
    public var lastPageRead: Int
    public var readAt: Date
    public var thumbnailUrl: String?
    public var customThumbnailUrl: String?
    public var sourceId: Int64
    public var mangaUrl: String
    public var chapterUrl: String
    public var isRead: Bool

    public init(
        id: Int64,
        chapterId: Int64,
        mangaId: Int64,
        mangaTitle: String,
        chapterName: String,
        chapterNumber: Float,
        lastPageRead: Int,
        readAt: Date,
        thumbnailUrl: String? = nil,
        customThumbnailUrl: String? = nil,
        sourceId: Int64,
        mangaUrl: String,
        chapterUrl: String,
        isRead: Bool
    ) {
        self.id = id
        self.chapterId = chapterId
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.chapterName = chapterName
        self.chapterNumber = chapterNumber
        self.lastPageRead = lastPageRead
        self.readAt = readAt
        self.thumbnailUrl = thumbnailUrl
        self.customThumbnailUrl = customThumbnailUrl
        self.sourceId = sourceId
        self.mangaUrl = mangaUrl
        self.chapterUrl = chapterUrl
        self.isRead = isRead
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

public final class HistoryRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches all reading history records in descending chronological order.
    public func getHistory(limit: Int = 100) async throws -> [HistoryItem] {
        try await dbManager.read { db in
            let sql = """
                SELECT
                    h.id AS history_id,
                    h.read_at,
                    c.id AS chapter_id,
                    c.manga_id,
                    c.name AS chapter_name,
                    c.chapter_number,
                    c.last_page_read,
                    c.read AS chapter_read,
                    c.url AS chapter_url,
                    m.title AS manga_title,
                    m.thumbnail_url,
                    m.custom_thumbnail_url,
                    m.source_id,
                    m.url AS manga_url
                FROM history h
                INNER JOIN chapters c ON c.id = h.chapter_id
                INNER JOIN mangas m ON m.id = c.manga_id
                ORDER BY h.read_at DESC, h.id DESC
                LIMIT ?
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [limit])
            return rows.map { row in
                HistoryItem(
                    id: row["history_id"],
                    chapterId: row["chapter_id"],
                    mangaId: row["manga_id"],
                    mangaTitle: row["manga_title"],
                    chapterName: row["chapter_name"],
                    chapterNumber: Float(row["chapter_number"] as Double? ?? -1.0),
                    lastPageRead: row["last_page_read"],
                    readAt: row["read_at"],
                    thumbnailUrl: row["thumbnail_url"],
                    customThumbnailUrl: row["custom_thumbnail_url"],
                    sourceId: row["source_id"],
                    mangaUrl: row["manga_url"],
                    chapterUrl: row["chapter_url"],
                    isRead: row["chapter_read"]
                )
            }
        }
    }

    /// Number of recorded history entries without materializing the full joined rows.
    public func getHistoryCount() async throws -> Int {
        try await dbManager.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history") ?? 0
        }
    }

    /// Deletes a specific history record by primary key.
    public func deleteHistoryItem(id: Int64) async throws {
        try await dbManager.write { db in
            try db.execute(sql: "DELETE FROM history WHERE id = ?", arguments: [id])
        }
    }

    /// Clears all entries from reading history.
    public func clearAllHistory() async throws {
        try await dbManager.write { db in
            try db.execute(sql: "DELETE FROM history")
        }
    }
}
