import Foundation
import GRDB
import YomiCore

public final class ExtensionRepoRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches all added third-party extension repositories.
    public func getAllRepos() async throws -> [ExtensionRepo] {
        try await dbManager.read { db in
            try ExtensionRepoRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Upserts a repository entry into the database.
    public func upsertRepo(_ repo: ExtensionRepo) async throws {
        try await dbManager.write { db in
            try ExtensionRepoRecord(repo: repo).save(db)
        }
    }

    /// Removes a repository by its base URL.
    public func deleteRepo(url: String) async throws {
        try await dbManager.write { db in
            _ = try ExtensionRepoRecord.deleteOne(db, key: url)
        }
    }
}
