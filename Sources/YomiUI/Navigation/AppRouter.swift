import Observation

/// Shared, lightweight navigation state used by tabs and empty-state calls to action.
@Observable
public final class AppRouter {
    public static let shared = AppRouter()

    public var selectedTab: AppTab = .library

    public init() {}

    public func openLibrary() {
        selectedTab = .library
    }

    public func openUpdates() {
        selectedTab = .updates
    }

    public func openHistory() {
        selectedTab = .history
    }

    public func openSources() {
        selectedTab = .sources
    }

    public func openBrowse() {
        selectedTab = .sources
    }

    public func openSettings() {
        selectedTab = .settings
    }
}
