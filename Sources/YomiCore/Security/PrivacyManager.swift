import Foundation
import Observation

/// Coordinates privacy defenses: Incognito Mode, App Switcher Snapshot Blur, and Secure Category Gates.
@Observable
public final class PrivacyManager: @unchecked Sendable {
    public static let shared = PrivacyManager()

    /// Incognito mode is active: suppresses history logging, suppresses tracker updates, and isolates cookies.
    public var isIncognitoMode: Bool = false

    /// When true, renders a secure blur overlay whenever the application loses active focus.
    public var isSnapshotProtectionEnabled: Bool {
        didSet { UserDefaults.standard.set(isSnapshotProtectionEnabled, forKey: "yomi_snapshot_protection") }
    }

    /// Whether the privacy shield overlay is currently displayed.
    public var isPrivacyShieldActive: Bool = false

    /// Set of unlocked secure category IDs for the current active session.
    private var unlockedCategoryIds: Set<Int64> = []

    private init() {
        self.isSnapshotProtectionEnabled = UserDefaults.standard.object(forKey: "yomi_snapshot_protection") as? Bool ?? true
    }

    /// Toggles Incognito mode on or off.
    public func toggleIncognito() {
        isIncognitoMode.toggle()
    }

    /// Engages privacy blur overlay upon app resignation.
    public func activatePrivacyShield() {
        if isSnapshotProtectionEnabled {
            isPrivacyShieldActive = true
        }
    }

    /// Dismisses privacy blur overlay upon app reactivation.
    public func deactivatePrivacyShield() {
        isPrivacyShieldActive = false
    }

    /// Checks if a category is locked and unlocked for the current session.
    public func isCategoryUnlocked(_ category: Category) -> Bool {
        guard category.isLocked, let id = category.id else { return true }
        return unlockedCategoryIds.contains(id)
    }

    /// Unlocks a category after successful biometric verification.
    public func unlockCategory(_ category: Category) {
        guard let id = category.id else { return }
        unlockedCategoryIds.insert(id)
    }

    /// Resets all category unlocks when the app locks.
    public func relockAllCategories() {
        unlockedCategoryIds.removeAll()
    }
}
