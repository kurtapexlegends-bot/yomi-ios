import Foundation

/// Defines how a manga should be laid out in the reader viewport.
public enum MangaViewer: Int, Codable, Sendable, CaseIterable {
    case defaultViewer = 0
    case leftToRight = 1
    case rightToLeft = 2
    case vertical = 3
    case webtoon = 4
    case continuousHorizontal = 5

    public var title: String {
        switch self {
        case .defaultViewer: return "Default"
        case .leftToRight: return "Left to Right"
        case .rightToLeft: return "Right to Left (Manga)"
        case .vertical: return "Vertical (Paged)"
        case .webtoon: return "Webtoon (Continuous)"
        case .continuousHorizontal: return "Continuous Horizontal"
        }
    }
}

/// Release status of a manga.
public enum MangaStatus: Int, Codable, Sendable {
    case unknown = 0
    case ongoing = 1
    case completed = 2
    case licensed = 3
    case publishingFinished = 4
    case cancelled = 5
    case onHiatus = 6

    public var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .ongoing: return "Ongoing"
        case .completed: return "Completed"
        case .licensed: return "Licensed"
        case .publishingFinished: return "Publishing Finished"
        case .cancelled: return "Cancelled"
        case .onHiatus: return "On Hiatus"
        }
    }
}

/// Core domain entity representing a manga entry in the library or search catalog.
public struct Manga: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64?
    public var sourceId: Int64
    public var url: String
    public var title: String
    public var author: String?
    public var artist: String?
    public var description: String?
    public var genres: [String]
    public var status: MangaStatus
    public var thumbnailUrl: String?
    public var customThumbnailUrl: String?
    public var inLibrary: Bool
    public var viewer: MangaViewer
    public var chapterFlags: Int
    public var dateAdded: Date
    public var lastUpdate: Date
    public var lastInit: Date

    public init(
        id: Int64? = nil,
        sourceId: Int64,
        url: String,
        title: String,
        author: String? = nil,
        artist: String? = nil,
        description: String? = nil,
        genres: [String] = [],
        status: MangaStatus = .unknown,
        thumbnailUrl: String? = nil,
        customThumbnailUrl: String? = nil,
        inLibrary: Bool = false,
        viewer: MangaViewer = .defaultViewer,
        chapterFlags: Int = 0,
        dateAdded: Date = Date(),
        lastUpdate: Date = Date(),
        lastInit: Date = Date()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.author = author
        self.artist = artist
        self.description = description
        self.genres = genres
        self.status = status
        self.thumbnailUrl = thumbnailUrl
        self.customThumbnailUrl = customThumbnailUrl
        self.inLibrary = inLibrary
        self.viewer = viewer
        self.chapterFlags = chapterFlags
        self.dateAdded = dateAdded
        self.lastUpdate = lastUpdate
        self.lastInit = lastInit
    }

    /// Returns the effective thumbnail to display, preferring user custom covers.
    public var effectiveThumbnailUrl: String? {
        customThumbnailUrl ?? thumbnailUrl
    }

    /// Unique identity key for SwiftUI lists, navigation, and diffing.
    /// Prefers the local database primary key if saved; falls back to source-scoped URL for catalog browsing.
    public var stableId: String {
        if let id = id {
            return "db_\(id)"
        }
        return "\(sourceId)_\(url)"
    }
}
