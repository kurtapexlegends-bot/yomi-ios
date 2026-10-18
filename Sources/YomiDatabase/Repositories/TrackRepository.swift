import Foundation
import GRDB
import YomiCore

public final class TrackRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches all tracking records for a manga.
    public func getTracks(forMangaId mangaId: Int64) async throws -> [Track] {
        try await dbManager.read { db in
            try TrackRecord
                .filter(Column("manga_id") == mangaId)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Fetches a specific tracker by manga ID and tracker service sync ID.
    public func getTrack(mangaId: Int64, syncId: Int) async throws -> Track? {
        try await dbManager.read { db in
            try TrackRecord
                .filter(Column("manga_id") == mangaId && Column("sync_id") == syncId)
                .fetchOne(db)?
                .toDomain()
        }
    }

    /// Upserts a tracker entry.
    @discardableResult
    public func upsertTrack(_ track: Track) async throws -> Track {
        try await dbManager.write { db in
            var record = TrackRecord(track: track)
            if let existing = try TrackRecord
                .filter(Column("manga_id") == track.mangaId && Column("sync_id") == track.syncId)
                .fetchOne(db) {
                record.id = existing.id
                try record.update(db)
            } else {
                try record.insert(db)
            }
            return record.toDomain()
        }
    }

    /// Deletes a tracking link.
    public func deleteTrack(id: Int64) async throws {
        try await dbManager.write { db in
            _ = try TrackRecord.deleteOne(db, id: id)
        }
    }
}
