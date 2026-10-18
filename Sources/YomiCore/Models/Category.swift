import Foundation

/// Represents a user-defined category or folder in the library.
public struct YomiCategory: Identifiable, Hashable, Codable, Sendable {
    public var id: Int64?
    public var name: String
    public var order: Int
    public var flags: Int
    public var isLocked: Bool

    public init(
        id: Int64? = nil,
        name: String,
        order: Int = 0,
        flags: Int = 0,
        isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.flags = flags
        self.isLocked = isLocked
    }

    /// Predefined default category for uncategorized manga.
    public static var defaultCategory: YomiCategory {
        YomiCategory(id: 0, name: "Default", order: 0, flags: 0, isLocked: false)
    }
}

