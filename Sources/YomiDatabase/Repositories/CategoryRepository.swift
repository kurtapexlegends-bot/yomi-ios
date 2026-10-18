import Foundation
import GRDB
import YomiCore

public final class CategoryRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Fetches all custom categories ordered by sort order.
    public func getAllCategories() async throws -> [Category] {
        try await dbManager.read { db in
            try CategoryRecord
                .order(Column("sort_order").asc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Creates a new user category.
    @discardableResult
    public func createCategory(name: String, isLocked: Bool = false) async throws -> Category {
        try await dbManager.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) FROM categories") ?? -1
            var record = CategoryRecord(category: Category(name: name, order: maxOrder + 1, flags: 0, isLocked: isLocked))
            try record.insert(db)
            return record.toDomain()
        }
    }

    /// Updates an existing category (rename, lock toggle).
    public func updateCategory(_ category: Category) async throws {
        try await dbManager.write { db in
            var record = CategoryRecord(category: category)
            try record.update(db)
        }
    }

    /// Deletes a category and unbinds its relations (does not delete manga).
    public func deleteCategory(id: Int64) async throws {
        try await dbManager.write { db in
            _ = try CategoryRecord.deleteOne(db, key: id)
        }
    }

    /// Updates category sort orders according to user drag-and-drop.
    public func reorderCategories(orderedIds: [Int64]) async throws {
        try await dbManager.write { db in
            for (index, id) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE categories SET sort_order = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    /// Associates a manga with a set of categories.
    public func setMangaCategories(mangaId: Int64, categoryIds: [Int64]) async throws {
        try await dbManager.write { db in
            try db.execute(sql: "DELETE FROM manga_categories WHERE manga_id = ?", arguments: [mangaId])
            for catId in categoryIds {
                try MangaCategoryRecord(mangaId: mangaId, categoryId: catId).insert(db)
            }
        }
    }

    /// Retrieves all category IDs a manga belongs to.
    public func getCategoryIds(forMangaId mangaId: Int64) async throws -> [Int64] {
        try await dbManager.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT category_id FROM manga_categories WHERE manga_id = ?",
                arguments: [mangaId]
            )
        }
    }
}
