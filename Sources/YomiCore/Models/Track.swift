import Foundation

/// Supported external tracking services.
public enum TrackerServiceType: Int, Codable, Sendable, CaseIterable {
    case aniList = 1
    case myAnimeList = 2
    case kitsu = 3
    case mangaUpdates = 4
    case shikimori = 5
    case bangumi = 6

    public var displayName: String {
        switch self {
        case .aniList: return "AniList"
        case .myAnimeList: return "MyAnimeList"
        case .kitsu: return "Kitsu"
        case .mangaUpdates: return "MangaUpdates"
        case .shikimori: return "Shikimori"
        case .bangumi: return "Bangumi"
        }
    }
}

/// Reading progress status on external trackers.
public enum TrackStatus: Int, Codable, Sendable, CaseIterable {
    case reading = 1
    case completed = 2
    case onHold = 3
    case dropped = 4
    case planToRead = 5
    case repeating = 6

    public var title: String {
        switch self {
        case .reading: return "Reading"
        case .completed: return "Completed"
        case .onHold: return "On Hold"
        case .dropped: return "Dropped"
        case .planToRead: return "Plan to Read"
        case .repeating: return "Rereading"
        }
    }
}

/// Entity representing an external tracker binding (AniList, MyAnimeList, etc.).
public struct Track: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64?
    public var mangaId: Int64
    public var syncId: Int
    public var remoteId: Int64
    public var libraryId: Int64?
    public var title: String
    public var lastChapterRead: Float
    public var totalChapters: Int
    public var score: Double
    public var status: TrackStatus
    public var startedReadingDate: Date?
    public var finishedReadingDate: Date?
    public var trackingUrl: String

    public init(
        id: Int64? = nil,
        mangaId: Int64,
        syncId: Int,
        remoteId: Int64,
        libraryId: Int64? = nil,
        title: String,
        lastChapterRead: Float = 0,
        totalChapters: Int = 0,
        score: Double = 0.0,
        status: TrackStatus = .reading,
        startedReadingDate: Date? = nil,
        finishedReadingDate: Date? = nil,
        trackingUrl: String = ""
    ) {
        self.id = id
        self.mangaId = mangaId
        self.syncId = syncId
        self.remoteId = remoteId
        self.libraryId = libraryId
        self.title = title
        self.lastChapterRead = lastChapterRead
        self.totalChapters = totalChapters
        self.score = score
        self.status = status
        self.startedReadingDate = startedReadingDate
        self.finishedReadingDate = finishedReadingDate
        self.trackingUrl = trackingUrl
    }
}
