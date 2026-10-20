import SwiftUI

/// Shared styling and building blocks for Yomi's settings view.
public struct SettingsGroup<Content: View>: View {
    public let title: String
    public let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(YomiFont.micro)
                .tracking(1.2)
                .foregroundStyle(YomiTheme.textTertiary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(YomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 0.5)
            )
        }
    }
}

public struct SettingsIcon: View {
    public let name: String
    public let tint: Color

    public init(_ name: String, tint: Color) {
        self.name = name
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

public struct SettingsInfoRow: View {
    public let icon: String
    public let tint: Color
    public let title: String
    public let value: String

    public init(icon: String, tint: Color, title: String, value: String) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon, tint: tint)
            Text(title)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textPrimary)
            Spacer()
            Text(value)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
        }
        .padding(.vertical, 10)
    }
}

public struct SettingsToggleRow: View {
    public let icon: String
    public let tint: Color
    public let title: String
    @Binding public var isOn: Bool

    public init(icon: String, tint: Color, title: String, isOn: Binding<Bool>) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon, tint: tint)
            Toggle(title, isOn: $isOn)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textPrimary)
                .tint(YomiTheme.accent)
        }
        .padding(.vertical, 4)
    }
}

public struct SettingsNavigationRow: View {
    public let icon: String
    public let tint: Color
    public let title: String
    public let value: String

    public init(icon: String, tint: Color, title: String, value: String) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon, tint: tint)
            Text(title)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textPrimary)
            Spacer()
            Text(value)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .padding(.vertical, 10)
    }
}
