import Foundation
import GRDB
import YomiCore

public final class MangaRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches a single manga by its local primary key.
    public func getManga(id: Int64) async throws -> Manga? {
        try await dbManager.read { db in
            try MangaRecord.fetchOne(db, id: id)?.toDomain()
        }
    }

    /// Fetches a manga by source and unique source URL.
    public func getManga(sourceId: Int64, url: String) async throws -> Manga? {
        try await dbManager.read { db in
            try MangaRecord
                .filter(Column("source_id") == sourceId && Column("url") == url)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// Returns all manga currently flagged as in the user's library.
    public func getLibraryMangas() async throws -> [Manga] {
        try await dbManager.read { db in
            try MangaRecord
                .filter(Column("in_library") == true)
                .order(Column("title").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Returns all manga belonging to a specific category.
    public func getLibraryMangas(forCategoryId categoryId: Int64) async throws -> [Manga] {
        try await dbManager.read { db in
            let sql = """
                SELECT m.* FROM mangas m
                INNER JOIN manga_categories mc ON mc.manga_id = m.id
                WHERE mc.category_id = ? AND m.in_library = 1
                ORDER BY m.title COLLATE NOCASE ASC
            """
            return try MangaRecord.fetchAll(db, sql: sql, arguments: [categoryId]).map { $0.toDomain() }
        }
    }

    /// Inserts or updates a manga entry, preserving local library state if existing.
    @discardableResult
    public func upsert(_ manga: Manga) async throws -> Manga {
        try await dbManager.write { db in
            var record = MangaRecord(manga: manga)
            if let existing = try MangaRecord
                .filter(Column("source_id") == manga.sourceId && Column("url") == manga.url)
                .fetchOne(db) {
                record.id = existing.id
                // Preserve user-controlled properties unless explicitly changing
                if !manga.inLibrary && existing.in_library {
                    record.in_library = existing.in_library
                    record.custom_thumbnail_url = existing.custom_thumbnail_url
                    record.viewer = existing.viewer
                }
                try record.update(db)
            } else {
                try record.insert(db)
            }
            return record.toDomain()
        }
    }

    /// Toggles or updates the favorite (in library) status of a manga.
    public func setInLibrary(mangaId: Int64, inLibrary: Bool) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE mangas SET in_library = ?, date_added = ? WHERE id = ?",
                arguments: [inLibrary, inLibrary ? Date() : Date(timeIntervalSince1970: 0), mangaId]
            )
        }
    }

    /// Updates the reading viewer preference for a specific manga.
    public func updateViewer(mangaId: Int64, viewer: MangaViewer) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE mangas SET viewer = ? WHERE id = ?",
                arguments: [viewer.rawValue, mangaId]
            )
        }
    }

    /// Performs instantaneous full-text search across titles, authors, and descriptions via FTS5.
    public func searchFTS(query: String) async throws -> [Manga] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return try await getLibraryMangas()
        }

        // Prepare FTS5 prefix query (e.g. "one piece" -> "one* piece*")
        let sanitized = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")

        return try await dbManager.read { db in
            let sql = """
                SELECT m.* FROM mangas m
                INNER JOIN mangas_fts ON mangas_fts.rowid = m.id
                WHERE mangas_fts MATCH ? AND m.in_library = 1
                ORDER BY rank
            """
            return try MangaRecord.fetchAll(db, sql: sql, arguments: [sanitized]).map { $0.toDomain() }
        }
    }

    /// Deletes a manga and its cascading chapters from disk.
    public func delete(id: Int64) async throws {
        try await dbManager.write { db in
            _ = try MangaRecord.deleteOne(db, id: id)
        }
    }
}
