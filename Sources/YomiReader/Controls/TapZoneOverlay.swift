import Foundation
import UIKit

public enum TapZoneLayout: Int, Codable, Sendable, CaseIterable {
    case leftRight = 0
    case kindle = 1
    case invertedL = 2
    case edgeOnly = 3
    case none = 4

    public var title: String {
        switch self {
        case .leftRight: return "Left / Right"
        case .kindle: return "Kindle Style"
        case .invertedL: return "Inverted L"
        case .edgeOnly: return "Edges Only"
        case .none: return "Swipes Only (Tap for Menu)"
        }
    }
}

public enum ReaderAction: Sendable {
    case previousPage
    case nextPage
    case toggleMenu
}

public enum TapZoneDetector {
    /// Determines the reader action based on touch location and configured layout.
    public static func action(for point: CGPoint, in bounds: CGRect, layout: TapZoneLayout, isRTL: Bool) -> ReaderAction {
        guard bounds.width > 0, bounds.height > 0 else { return .toggleMenu }

        let normalizedX = point.x / bounds.width
        let normalizedY = point.y / bounds.height

        switch layout {
        case .leftRight:
            if normalizedX < 0.30 {
                return isRTL ? .nextPage : .previousPage
            } else if normalizedX > 0.70 {
                return isRTL ? .previousPage : .nextPage
            } else {
                return .toggleMenu
            }

        case .kindle:
            if normalizedY < 0.20 && (normalizedX > 0.25 && normalizedX < 0.75) {
                return .toggleMenu
            } else if normalizedX < 0.20 {
                return isRTL ? .nextPage : .previousPage
            } else {
                return isRTL ? .previousPage : .nextPage
            }

        case .invertedL:
            if (normalizedX < 0.30 && normalizedY < 0.70) || (normalizedY < 0.30 && normalizedX < 0.70) {
                return isRTL ? .nextPage : .previousPage
            } else if normalizedX > 0.30 && normalizedX < 0.70 && normalizedY > 0.30 && normalizedY < 0.70 {
                return .toggleMenu
            } else {
                return isRTL ? .previousPage : .nextPage
            }

        case .edgeOnly:
            if normalizedX < 0.15 {
                return isRTL ? .nextPage : .previousPage
            } else if normalizedX > 0.85 {
                return isRTL ? .previousPage : .nextPage
            } else {
                return .toggleMenu
            }

        case .none:
            return .toggleMenu
        }
    }
}
