import Observation

/// Shared, lightweight navigation state used by tabs and empty-state calls to action.
@Observable
public final class AppRouter {
    public static let shared = AppRouter()

    public var selectedTab: AppTab = .library

    public init() {}

    public func openBrowse() {
        selectedTab = .browse
    }

    public func openLibrary() {
        selectedTab = .library
    }

    public func openUpdates() {
        selectedTab = .updates
    }
}
