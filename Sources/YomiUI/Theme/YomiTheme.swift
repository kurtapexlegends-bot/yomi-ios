import SwiftUI

/// Yomi's OLED-first visual language.
///
/// The palette is intentionally small: true black canvas, one violet accent, two neutral
/// surfaces, and semantic status colors. Views should compose these tokens rather than
/// inventing per-screen colors.
public enum YomiTheme {
    /// True OLED Black (#000000) canvas where pixels physically shut off.
    public static let pureBlack = Color.black
    public static let background = pureBlack

    /// Neutral architectural dark surfaces (no muddy blue or purple tints).
    public static let surface = Color(red: 0.067, green: 0.067, blue: 0.075) // #111113
    public static let elevatedSurface = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    public static let sunkenSurface = Color(red: 0.035, green: 0.035, blue: 0.040) // #09090A

    /// Subtle hairline strokes replacing thick border outlines.
    public static let border = Color.white.opacity(0.065)
    public static let borderStrong = Color.white.opacity(0.12)

    /// Restrained electric violet (#7C5CFC) strictly for focal interaction points.
    public static let accent = Color(red: 0.486, green: 0.361, blue: 0.988)
    public static let accentStrong = Color(red: 0.545, green: 0.435, blue: 0.992)
    public static let accentSoft = Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.14)

    public static let unreadBadge = Color(red: 0.420, green: 0.580, blue: 1.000)
    public static let downloadBadge = Color(red: 0.290, green: 0.840, blue: 0.520)
    public static let success = Color(red: 0.290, green: 0.840, blue: 0.520)
    public static let warning = Color(red: 1.000, green: 0.720, blue: 0.300)
    public static let danger = Color(red: 1.000, green: 0.370, blue: 0.420)

    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.65)
    public static let textTertiary = Color(red: 0.38, green: 0.38, blue: 0.42)

    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 18

    public static let contentPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 12
}

/// Editorial San Francisco typography with crisp hierarchy and zero cartoonish rounded edges.
public enum YomiFont {
    public static let screenTitle = Font.system(size: 28, weight: .bold)
    public static let screenSubtitle = Font.system(size: 13, weight: .regular)
    public static let sectionTitle = Font.system(size: 18, weight: .semibold)
    public static let cardTitle = Font.system(size: 14, weight: .semibold)
    public static let body = Font.system(size: 14, weight: .regular)
    public static let caption = Font.system(size: 12, weight: .regular)
    public static let micro = Font.system(size: 10, weight: .semibold)
    public static let number = Font.system(size: 13, weight: .semibold).monospacedDigit()
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var strokeColor: Color

    public init(
        cornerRadius: CGFloat = YomiTheme.cornerRadiusMedium,
        strokeColor: Color = YomiTheme.borderStrong
    ) {
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
    }

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 5)
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = YomiTheme.cornerRadiusMedium, strokeColor: Color = YomiTheme.borderStrong) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeColor: strokeColor))
    }
}
