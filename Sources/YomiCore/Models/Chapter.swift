import Foundation

/// Core domain entity representing a single chapter of a manga.
public struct Chapter: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64?
    public var mangaId: Int64
    public var url: String
    public var name: String
    public var scanlator: String?
    public var read: Bool
    public var bookmark: Bool
    public var lastPageRead: Int
    public var chapterNumber: Float
    public var sourceOrder: Int
    public var dateFetch: Date
    public var dateUpload: Date
    public var lastModifiedAt: Date

    public init(
        id: Int64? = nil,
        mangaId: Int64,
        url: String,
        name: String,
        scanlator: String? = nil,
        read: Bool = false,
        bookmark: Bool = false,
        lastPageRead: Int = 0,
        chapterNumber: Float = -1.0,
        sourceOrder: Int = 0,
        dateFetch: Date = Date(),
        dateUpload: Date = Date(),
        lastModifiedAt: Date = Date()
    ) {
        self.id = id
        self.mangaId = mangaId
        self.url = url
        self.name = name
        self.scanlator = scanlator
        self.read = read
        self.bookmark = bookmark
        self.lastPageRead = lastPageRead
        self.chapterNumber = chapterNumber
        self.sourceOrder = sourceOrder
        self.dateFetch = dateFetch
        self.dateUpload = dateUpload
        self.lastModifiedAt = lastModifiedAt
    }

    /// Formatted chapter display title (e.g., "Ch. 12 - Title" or "Chapter 12").
    public var displayTitle: String {
        if chapterNumber >= 0 {
            let formattedNumber = chapterNumber.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", chapterNumber)
                : String(format: "%.1f", chapterNumber)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                return "Ch. \(formattedNumber)"
            }
            if trimmedName.lowercased().hasPrefix("chapter") || trimmedName.lowercased().hasPrefix("ch.") {
                return trimmedName
            }
            return "Ch. \(formattedNumber) — \(trimmedName)"
        }
        return name.isEmpty ? "Chapter" : name
    }

    /// Unique identity key for SwiftUI lists, navigation, and diffing.
    public var stableId: String {
        if let id = id {
            return "ch_\(id)"
        }
        return "ch_\(mangaId)_\(url)"
    }
}
