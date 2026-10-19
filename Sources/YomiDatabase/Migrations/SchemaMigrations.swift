import Foundation
import GRDB
import YomiCore

public enum SchemaMigrations {
    /// Registers all database schema migrations in chronological sequence.
    public static func registerMigrations(in migrator: inout DatabaseMigrator) {
        
        // MARK: - v1: Initial Core Schema
        migrator.registerMigration("v1_initial_tables") { db in
            // Manga table
            try db.create(table: "mangas") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("source_id", .integer).notNull().indexed()
                t.column("url", .text).notNull()
                t.column("title", .text).notNull().indexed()
                t.column("author", .text)
                t.column("artist", .text)
                t.column("description", .text)
                t.column("genres", .text).notNull().defaults(to: "[]")
                t.column("status", .integer).notNull().defaults(to: 0)
                t.column("thumbnail_url", .text)
                t.column("custom_thumbnail_url", .text)
                t.column("in_library", .boolean).notNull().defaults(to: false).indexed()
                t.column("viewer", .integer).notNull().defaults(to: 0)
                t.column("chapter_flags", .integer).notNull().defaults(to: 0)
                t.column("date_added", .datetime).notNull()
                t.column("last_update", .datetime).notNull()
                t.column("last_init", .datetime).notNull()
                t.uniqueKey(["source_id", "url"])
            }

            // Chapters table
            try db.create(table: "chapters") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("manga_id", .integer).notNull().references("mangas", onDelete: .cascade).indexed()
                t.column("url", .text).notNull()
                t.column("name", .text).notNull()
                t.column("scanlator", .text)
                t.column("read", .boolean).notNull().defaults(to: false).indexed()
                t.column("bookmark", .boolean).notNull().defaults(to: false).indexed()
                t.column("last_page_read", .integer).notNull().defaults(to: 0)
                t.column("chapter_number", .double).notNull().defaults(to: -1.0).indexed()
                t.column("source_order", .integer).notNull().defaults(to: 0)
                t.column("date_fetch", .datetime).notNull()
                t.column("date_upload", .datetime).notNull()
                t.column("last_modified_at", .datetime).notNull()
                t.uniqueKey(["manga_id", "url"])
            }

            // Categories table
            try db.create(table: "categories") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("flags", .integer).notNull().defaults(to: 0)
                t.column("is_locked", .boolean).notNull().defaults(to: false)
            }

            // Manga-Categories Join Table
            try db.create(table: "manga_categories") { t in
                t.column("manga_id", .integer).notNull().references("mangas", onDelete: .cascade)
                t.column("category_id", .integer).notNull().references("categories", onDelete: .cascade)
                t.primaryKey(["manga_id", "category_id"])
            }

            // Reading History table
            try db.create(table: "history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("chapter_id", .integer).notNull().references("chapters", onDelete: .cascade).indexed()
                t.column("read_at", .datetime).notNull().indexed()
            }

            // External Trackers table (AniList, MyAnimeList)
            try db.create(table: "tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("manga_id", .integer).notNull().references("mangas", onDelete: .cascade).indexed()
                t.column("sync_id", .integer).notNull()
                t.column("remote_id", .integer).notNull()
                t.column("library_id", .integer)
                t.column("title", .text).notNull()
                t.column("last_chapter_read", .double).notNull().defaults(to: 0)
                t.column("total_chapters", .integer).notNull().defaults(to: 0)
                t.column("score", .double).notNull().defaults(to: 0)
                t.column("status", .integer).notNull().defaults(to: 1)
                t.column("started_reading_date", .datetime)
                t.column("finished_reading_date", .datetime)
                t.column("tracking_url", .text).notNull().defaults(to: "")
                t.uniqueKey(["manga_id", "sync_id"])
            }

            // Community Extension Repositories table
            try db.create(table: "extension_repos") { t in
                t.column("url", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("website_url", .text)
                t.column("sources_count", .integer).notNull().defaults(to: 0)
                t.column("last_checked", .datetime).notNull()
            }

            // Installed Sources table
            try db.create(table: "installed_sources") { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("lang", .text).notNull()
                t.column("base_url", .text).notNull()
                t.column("icon_url", .text)
                t.column("version", .text).notNull()
                t.column("is_configurable", .boolean).notNull().defaults(to: false)
                t.column("supports_latest", .boolean).notNull().defaults(to: true)
                t.column("is_nsfw", .boolean).notNull().defaults(to: false)
                t.column("js_script_path", .text)
                t.column("repo_url", .text)
            }
        }

        // MARK: - v2: FTS5 Full-Text Search Virtual Table & Automatic Triggers
        migrator.registerMigration("v2_fts5_search") { db in
            // Create FTS5 virtual table indexing title, author, artist, and description
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS mangas_fts USING fts5(
                    title,
                    author,
                    artist,
                    description,
                    content='mangas',
                    content_rowid='id'
                );
            """)

            // Trigger for automatic INSERT sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS mangas_fts_insert AFTER INSERT ON mangas BEGIN
                    INSERT INTO mangas_fts(rowid, title, author, artist, description)
                    VALUES (new.id, new.title, new.author, new.artist, new.description);
                END;
            """)

            // Trigger for automatic UPDATE sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS mangas_fts_update AFTER UPDATE ON mangas BEGIN
                    INSERT INTO mangas_fts(mangas_fts, rowid, title, author, artist, description)
                    VALUES('delete', old.id, old.title, old.author, old.artist, old.description);
                    INSERT INTO mangas_fts(rowid, title, author, artist, description)
                    VALUES (new.id, new.title, new.author, new.artist, new.description);
                END;
            """)

            // Trigger for automatic DELETE sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS mangas_fts_delete AFTER DELETE ON mangas BEGIN
                    INSERT INTO mangas_fts(mangas_fts, rowid, title, author, artist, description)
                    VALUES('delete', old.id, old.title, old.author, old.artist, old.description);
                END;
            """)
        }

        // MARK: - v3: Seed Default Keiyoushi Repository
        migrator.registerMigration("v3_seed_keiyoushi_repo") { db in
            let defaultRepo = ExtensionRepo(
                name: "Keiyoushi",
                url: "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json",
                websiteUrl: "https://keiyoushi.github.io",
                sourcesCount: 0,
                lastChecked: Date()
            )
            try ExtensionRepoRecord(repo: defaultRepo).insert(db, onConflict: .ignore)
        }
    }
}
