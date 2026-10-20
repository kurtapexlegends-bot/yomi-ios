import SwiftUI

/// Yomi's OLED-first visual language.
///
/// The palette is intentionally small: true black canvas, one violet accent, two neutral
/// surfaces, and semantic status colors. Views should compose these tokens rather than
/// inventing per-screen colors.
public enum YomiTheme {
    public static let pureBlack = Color(red: 0.016, green: 0.016, blue: 0.024)
    public static let background = pureBlack

    public static let surface = Color(red: 0.070, green: 0.070, blue: 0.090)
    public static let elevatedSurface = Color(red: 0.105, green: 0.105, blue: 0.132)
    public static let sunkenSurface = Color(red: 0.040, green: 0.040, blue: 0.055)

    public static let border = Color.white.opacity(0.085)
    public static let borderStrong = Color.white.opacity(0.16)

    public static let accent = Color(red: 0.486, green: 0.361, blue: 0.988)
    public static let accentStrong = Color(red: 0.580, green: 0.470, blue: 1.000)
    public static let accentSoft = Color(red: 0.486, green: 0.361, blue: 0.988).opacity(0.16)

    public static let unreadBadge = Color(red: 0.420, green: 0.580, blue: 1.000)
    public static let downloadBadge = Color(red: 0.290, green: 0.840, blue: 0.520)
    public static let success = Color(red: 0.290, green: 0.840, blue: 0.520)
    public static let warning = Color(red: 1.000, green: 0.720, blue: 0.300)
    public static let danger = Color(red: 1.000, green: 0.370, blue: 0.420)

    public static let textPrimary = Color(red: 0.960, green: 0.960, blue: 0.980)
    public static let textSecondary = Color(red: 0.610, green: 0.610, blue: 0.670)
    public static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.480)

    public static let cornerRadiusSmall: CGFloat = 10
    public static let cornerRadiusMedium: CGFloat = 16
    public static let cornerRadiusLarge: CGFloat = 22

    public static let contentPadding: CGFloat = 20
    public static let cardSpacing: CGFloat = 14
}

public enum YomiFont {
    public static let screenTitle = Font.system(size: 32, weight: .bold, design: .rounded)
    public static let screenSubtitle = Font.system(size: 13, weight: .medium, design: .rounded)
    public static let sectionTitle = Font.system(size: 19, weight: .bold, design: .rounded)
    public static let cardTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    public static let body = Font.system(size: 14, weight: .regular, design: .rounded)
    public static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    public static let micro = Font.system(size: 10, weight: .bold, design: .rounded)
    public static let number = Font.system(size: 13, weight: .semibold, design: .monospaced)
}

public struct GlassCardModifier: ViewModifier {
    public init() {}

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
