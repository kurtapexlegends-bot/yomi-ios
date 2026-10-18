import SwiftUI

#if canImport(UIKit)
import UIKit

public enum YomiTheme {
    public static let pureBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let surface = Color(UIColor.secondarySystemBackground)
    public static let elevatedSurface = Color(UIColor.tertiarySystemBackground)
    public static let accent = Color.indigo
    public static let unreadBadge = Color.blue
    public static let downloadBadge = Color.green
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary

    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16
}
#else
public enum YomiTheme {
    public static let pureBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let surface = Color.gray.opacity(0.15)
    public static let elevatedSurface = Color.gray.opacity(0.25)
    public static let accent = Color.indigo
    public static let unreadBadge = Color.blue
    public static let downloadBadge = Color.green
    public static let textPrimary = Color.primary
    public static let textSecondary = Color.secondary

    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 16
}
#endif

public struct GlassCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
    }
}

public extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
