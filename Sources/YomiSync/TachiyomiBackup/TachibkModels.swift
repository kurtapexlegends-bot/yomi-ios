import Foundation

/// Models matching Tachiyomi / Mihon .tachibk backup structures for frictionless cross-platform migration.
public struct TachibkRoot: Codable, Sendable {
    public var backupManga: [BackupManga]
    public var backupCategories: [BackupCategory]
    public var backupSources: [BackupSource]

    public init(
        backupManga: [BackupManga] = [],
        backupCategories: [BackupCategory] = [],
        backupSources: [BackupSource] = []
    ) {
        self.backupManga = backupManga
        self.backupCategories = backupCategories
        self.backupSources = backupSources
    }
}

public struct BackupManga: Codable, Sendable {
    public var source: Int64
    public var url: String
    public var title: String
    public var artist: String?
    public var author: String?
    public var description: String?
    public var genre: [String]
    public var status: Int
    public var thumbnailUrl: String?
    public var customThumbnailUrl: String?
    public var favorite: Bool
    public var viewer: Int
    public var chapterFlags: Int
    public var chapters: [BackupChapter]
    public var categories: [Int]
    public var tracking: [BackupTracking]

    public init(
        source: Int64,
        url: String,
        title: String,
        artist: String? = nil,
        author: String? = nil,
        description: String? = nil,
        genre: [String] = [],
        status: Int = 0,
        thumbnailUrl: String? = nil,
        customThumbnailUrl: String? = nil,
        favorite: Bool = true,
        viewer: Int = 0,
        chapterFlags: Int = 0,
        chapters: [BackupChapter] = [],
        categories: [Int] = [],
        tracking: [BackupTracking] = []
    ) {
        self.source = source
        self.url = url
        self.title = title
        self.artist = artist
        self.author = author
        self.description = description
        self.genre = genre
        self.status = status
        self.thumbnailUrl = thumbnailUrl
        self.customThumbnailUrl = customThumbnailUrl
        self.favorite = favorite
        self.viewer = viewer
        self.chapterFlags = chapterFlags
        self.chapters = chapters
        self.categories = categories
        self.tracking = tracking
    }
}

public struct BackupChapter: Codable, Sendable {
    public var url: String
    public var name: String
    public var scanlator: String?
    public var read: Bool
    public var bookmark: Bool
    public var lastPageRead: Int
    public var dateFetch: Int64
    public var dateUpload: Int64
    public var chapterNumber: Float
    public var sourceOrder: Int

    public init(
        url: String,
        name: String,
        scanlator: String? = nil,
        read: Bool = false,
        bookmark: Bool = false,
        lastPageRead: Int = 0,
        dateFetch: Int64 = 0,
        dateUpload: Int64 = 0,
        chapterNumber: Float = -1.0,
        sourceOrder: Int = 0
    ) {
        self.url = url
        self.name = name
        self.scanlator = scanlator
        self.read = read
        self.bookmark = bookmark
        self.lastPageRead = lastPageRead
        self.dateFetch = dateFetch
        self.dateUpload = dateUpload
        self.chapterNumber = chapterNumber
        self.sourceOrder = sourceOrder
    }
}

public struct BackupCategory: Codable, Sendable {
    public var name: String
    public var order: Int
    public var flags: Int

    public init(name: String, order: Int = 0, flags: Int = 0) {
        self.name = name
        self.order = order
        self.flags = flags
    }
}

public struct BackupTracking: Codable, Sendable {
    public var syncId: Int
    public var libraryId: Int64?
    public var mediaIdInt: Int64
    public var trackingUrl: String
    public var title: String
    public var lastChapterRead: Float
    public var totalChapters: Int
    public var score: Float
    public var status: Int

    public init(
        syncId: Int,
        libraryId: Int64? = nil,
        mediaIdInt: Int64,
        trackingUrl: String = "",
        title: String,
        lastChapterRead: Float = 0,
        totalChapters: Int = 0,
        score: Float = 0.0,
        status: Int = 1
    ) {
        self.syncId = syncId
        self.libraryId = libraryId
        self.mediaIdInt = mediaIdInt
        self.trackingUrl = trackingUrl
        self.title = title
        self.lastChapterRead = lastChapterRead
        self.totalChapters = totalChapters
        self.score = score
        self.status = status
    }
}

public struct BackupSource: Codable, Sendable {
    public var name: String
    public var sourceId: Int64

    public init(name: String, sourceId: Int64) {
        self.name = name
        self.sourceId = sourceId
    }
}
