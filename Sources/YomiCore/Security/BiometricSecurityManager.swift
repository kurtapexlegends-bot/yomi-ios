import Foundation
import LocalAuthentication
import Observation

/// Configurable lock timer grace period.
public enum LockGracePeriod: Int, Codable, Sendable, CaseIterable {
    case immediately = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800

    public var title: String {
        switch self {
        case .immediately: return "Immediately"
        case .oneMinute: return "After 1 minute"
        case .twoMinutes: return "After 2 minutes"
        case .fiveMinutes: return "After 5 minutes"
        case .tenMinutes: return "After 10 minutes"
        case .thirtyMinutes: return "After 30 minutes"
        }
    }
}

/// Supported biometric hardware type on the device.
public enum BiometricType: Sendable {
    case none
    case touchID
    case faceID
    case opticID

    public var title: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
}

/// Coordinates Face ID / Touch ID / Passcode biometric locks and session timeouts.
@Observable
public final class BiometricSecurityManager: @unchecked Sendable {
    public static let shared = BiometricSecurityManager()

    public var isAppLockEnabled: Bool {
        didSet { UserDefaults.standard.set(isAppLockEnabled, forKey: "yomi_app_lock_enabled") }
    }
    public var gracePeriod: LockGracePeriod {
        didSet { UserDefaults.standard.set(gracePeriod.rawValue, forKey: "yomi_lock_grace_period") }
    }
    public var isUnlocked: Bool = false
    public var lastBackgroundTime: Date?

    private init() {
        self.isAppLockEnabled = UserDefaults.standard.bool(forKey: "yomi_app_lock_enabled")
        let savedGrace = UserDefaults.standard.integer(forKey: "yomi_lock_grace_period")
        self.gracePeriod = LockGracePeriod(rawValue: savedGrace) ?? .immediately
        self.isUnlocked = !isAppLockEnabled
    }

    /// Evaluates device hardware for biometric support.
    public func availableBiometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        case .none: return .none
        @unknown default: return .none
        }
    }

    /// Request biometric verification to unlock the app or restricted category.
    @MainActor
    public func requestUnlock(reason: String = "Unlock Yomi") async -> Bool {
        guard isAppLockEnabled else {
            self.isUnlocked = true
            return true
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if success {
                self.isUnlocked = true
                self.lastBackgroundTime = nil
            }
            return success
        } catch {
            return false
        }
    }

    /// Handles app transition to background, recording the timestamp.
    public func handleAppDidEnterBackground() {
        guard isAppLockEnabled else { return }
        lastBackgroundTime = Date()
    }

    /// Handles app transition to foreground, evaluating grace periods.
    public func handleAppWillEnterForeground() {
        guard isAppLockEnabled else {
            isUnlocked = true
            return
        }

        guard let lastBackground = lastBackgroundTime else {
            isUnlocked = false
            return
        }

        let elapsed = Date().timeIntervalSince(lastBackground)
        if elapsed > Double(gracePeriod.rawValue) {
            isUnlocked = false
        }
    }

    /// Force locks the application immediately.
    public func lockImmediately() {
        if isAppLockEnabled {
            isUnlocked = false
        }
    }
}
