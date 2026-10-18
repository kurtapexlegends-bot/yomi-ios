import Foundation
import GRDB
import YomiCore

// MARK: - Manga Record
public struct MangaRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    public static let databaseTableName = "mangas"

    public var id: Int64?
    public var source_id: Int64
    public var url: String
    public var title: String
    public var author: String?
    public var artist: String?
    public var description: String?
    public var genres: String
    public var status: Int
    public var thumbnail_url: String?
    public var custom_thumbnail_url: String?
    public var in_library: Bool
    public var viewer: Int
    public var chapter_flags: Int
    public var date_added: Date
    public var last_update: Date
    public var last_init: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(manga: Manga) {
        self.id = manga.id
        self.source_id = manga.sourceId
        self.url = manga.url
        self.title = manga.title
        self.author = manga.author
        self.artist = manga.artist
        self.description = manga.description
        if let encoded = try? JSONEncoder().encode(manga.genres),
           let json = String(data: encoded, encoding: .utf8) {
            self.genres = json
        } else {
            self.genres = "[]"
        }
        self.status = manga.status.rawValue
        self.thumbnail_url = manga.thumbnailUrl
        self.custom_thumbnail_url = manga.customThumbnailUrl
        self.in_library = manga.inLibrary
        self.viewer = manga.viewer.rawValue
        self.chapter_flags = manga.chapterFlags
        self.date_added = manga.dateAdded
        self.last_update = manga.lastUpdate
        self.last_init = manga.lastInit
    }

    public func toDomain() -> Manga {
        var parsedGenres: [String] = []
        if let data = genres.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            parsedGenres = decoded
        }

        return Manga(
            id: id,
            sourceId: source_id,
            url: url,
            title: title,
            author: author,
            artist: artist,
            description: description,
            genres: parsedGenres,
            status: MangaStatus(rawValue: status) ?? .unknown,
            thumbnailUrl: thumbnail_url,
            customThumbnailUrl: custom_thumbnail_url,
            inLibrary: in_library,
            viewer: MangaViewer(rawValue: viewer) ?? .defaultViewer,
            chapterFlags: chapter_flags,
            dateAdded: date_added,
            lastUpdate: last_update,
            lastInit: last_init
        )
    }
}

// MARK: - Chapter Record
public struct ChapterRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    public static let databaseTableName = "chapters"

    public var id: Int64?
    public var manga_id: Int64
    public var url: String
    public var name: String
    public var scanlator: String?
    public var read: Bool
    public var bookmark: Bool
    public var last_page_read: Int
    public var chapter_number: Double
    public var source_order: Int
    public var date_fetch: Date
    public var date_upload: Date
    public var last_modified_at: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(chapter: Chapter) {
        self.id = chapter.id
        self.manga_id = chapter.mangaId
        self.url = chapter.url
        self.name = chapter.name
        self.scanlator = chapter.scanlator
        self.read = chapter.read
        self.bookmark = chapter.bookmark
        self.last_page_read = chapter.lastPageRead
        self.chapter_number = Double(chapter.chapterNumber)
        self.source_order = chapter.sourceOrder
        self.date_fetch = chapter.dateFetch
        self.date_upload = chapter.dateUpload
        self.last_modified_at = chapter.lastModifiedAt
    }

    public func toDomain() -> Chapter {
        Chapter(
            id: id,
            mangaId: manga_id,
            url: url,
            name: name,
            scanlator: scanlator,
            read: read,
            bookmark: bookmark,
            lastPageRead: last_page_read,
            chapterNumber: Float(chapter_number),
            sourceOrder: source_order,
            dateFetch: date_fetch,
            dateUpload: date_upload,
            lastModifiedAt: last_modified_at
        )
    }
}

// MARK: - Category Record
public struct CategoryRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    public static let databaseTableName = "categories"

    public var id: Int64?
    public var name: String
    public var sort_order: Int
    public var flags: Int
    public var is_locked: Bool

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(category: Category) {
        self.id = category.id
        self.name = category.name
        self.sort_order = category.order
        self.flags = category.flags
        self.is_locked = category.isLocked
    }

    public func toDomain() -> Category {
        Category(
            id: id,
            name: name,
            order: sort_order,
            flags: flags,
            isLocked: is_locked
        )
    }
}

// MARK: - Manga Category Record
public struct MangaCategoryRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "manga_categories"

    public var manga_id: Int64
    public var category_id: Int64

    public init(mangaId: Int64, categoryId: Int64) {
        self.manga_id = mangaId
        self.category_id = categoryId
    }
}

// MARK: - Track Record
public struct TrackRecord: Codable, FetchableRecord, MutablePersistableRecord, TableRecord {
    public static let databaseTableName = "tracks"

    public var id: Int64?
    public var manga_id: Int64
    public var sync_id: Int
    public var remote_id: Int64
    public var library_id: Int64?
    public var title: String
    public var last_chapter_read: Double
    public var total_chapters: Int
    public var score: Double
    public var status: Int
    public var started_reading_date: Date?
    public var finished_reading_date: Date?
    public var tracking_url: String

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(track: Track) {
        self.id = track.id
        self.manga_id = track.mangaId
        self.sync_id = track.syncId
        self.remote_id = track.remoteId
        self.library_id = track.libraryId
        self.title = track.title
        self.last_chapter_read = Double(track.lastChapterRead)
        self.total_chapters = track.totalChapters
        self.score = track.score
        self.status = track.status.rawValue
        self.started_reading_date = track.startedReadingDate
        self.finished_reading_date = track.finishedReadingDate
        self.tracking_url = track.trackingUrl
    }

    public func toDomain() -> Track {
        Track(
            id: id,
            mangaId: manga_id,
            syncId: sync_id,
            remoteId: remote_id,
            libraryId: library_id,
            title: title,
            lastChapterRead: Float(last_chapter_read),
            totalChapters: total_chapters,
            score: score,
            status: TrackStatus(rawValue: status) ?? .reading,
            startedReadingDate: started_reading_date,
            finishedReadingDate: finished_reading_date,
            trackingUrl: tracking_url
        )
    }
}

// MARK: - Extension Repo Record
public struct ExtensionRepoRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "extension_repos"

    public var url: String
    public var name: String
    public var website_url: String?
    public var sources_count: Int
    public var last_checked: Date

    public init(repo: ExtensionRepo) {
        self.url = repo.url
        self.name = repo.name
        self.website_url = repo.websiteUrl
        self.sources_count = repo.sourcesCount
        self.last_checked = repo.lastChecked
    }

    public func toDomain() -> ExtensionRepo {
        ExtensionRepo(
            name: name,
            url: url,
            websiteUrl: website_url,
            sourcesCount: sources_count,
            lastChecked: last_checked
        )
    }
}
