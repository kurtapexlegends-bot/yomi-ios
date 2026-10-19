import Foundation

/// Defines a manga source (extension or built-in connector).
public struct SourceManifest: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64
    public var name: String
    public var lang: String
    public var baseUrl: String
    public var iconUrl: String?
    public var version: String
    public var isConfigurable: Bool
    public var supportsLatest: Bool
    public var isNsfw: Bool

    public init(
        id: Int64,
        name: String,
        lang: String = "en",
        baseUrl: String,
        iconUrl: String? = nil,
        version: String = "1.0.0",
        isConfigurable: Bool = false,
        supportsLatest: Bool = true,
        isNsfw: Bool = false
    ) {
        self.id = id
        self.name = name
        self.lang = lang
        self.baseUrl = baseUrl
        self.iconUrl = iconUrl
        self.version = version
        self.isConfigurable = isConfigurable
        self.supportsLatest = supportsLatest
        self.isNsfw = isNsfw
    }
}

/// A single page inside a chapter.
public struct ReaderPage: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(index)_\(url)" }
    public var index: Int
    public var url: String
    public var imageUrl: String?
    public var headers: [String: String]
    public var localPath: String?

    public init(
        index: Int,
        url: String,
        imageUrl: String? = nil,
        headers: [String: String] = [:],
        localPath: String? = nil
    ) {
        self.index = index
        self.url = url
        self.imageUrl = imageUrl
        self.headers = headers
        self.localPath = localPath
    }
}

/// Paginated listing result returned by sources.
public struct MangaPageResult: Sendable {
    public let mangas: [Manga]
    public let hasNextPage: Bool

    public init(mangas: [Manga], hasNextPage: Bool) {
        self.mangas = mangas
        self.hasNextPage = hasNextPage
    }
}

/// Tri-state filter state (included, excluded, ignored).
public enum TriState: Int, Codable, Sendable {
    case ignored = 0
    case included = 1
    case excluded = 2
}

/// Dynamic filter representation for sources.
public enum Filter: Identifiable, Sendable, Equatable, Hashable {
    case text(id: String, name: String, state: String)
    case select(id: String, name: String, values: [String], selectedIndex: Int)
    case triState(id: String, name: String, state: TriState)
    case sort(id: String, name: String, values: [String], selectedIndex: Int, ascending: Bool)

    public var id: String {
        switch self {
        case .text(let id, _, _): return id
        case .select(let id, _, _, _): return id
        case .triState(let id, _, _): return id
        case .sort(let id, _, _, _, _): return id
        }
    }

    public var name: String {
        switch self {
        case .text(_, let name, _): return name
        case .select(_, let name, _, _): return name
        case .triState(_, let name, _): return name
        case .sort(_, let name, _, _, _): return name
        }
    }

    public var isDefault: Bool {
        switch self {
        case .text(_, _, let state):
            return state.isEmpty
        case .select(_, _, _, let selectedIndex):
            return selectedIndex == 0
        case .triState(_, _, let state):
            return state == .ignored
        case .sort(_, _, _, let selectedIndex, let ascending):
            return selectedIndex == 0 && !ascending
        }
    }
}
