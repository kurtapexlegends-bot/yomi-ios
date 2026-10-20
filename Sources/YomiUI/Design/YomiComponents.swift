import SwiftUI

// MARK: - Background

/// True-black OLED canvas (#000000). Pixels physically power down for infinite contrast.
public struct YomiBackground: View {
    public let showsGlow: Bool

    public init(showsGlow: Bool = false) {
        self.showsGlow = showsGlow
    }

    public var body: some View {
        YomiTheme.background
            .ignoresSafeArea()
    }
}

// MARK: - Typography blocks

public struct YomiEyebrow: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(YomiFont.micro)
            .tracking(1.4)
            .foregroundStyle(YomiTheme.accentStrong)
    }
}

public struct YomiScreenHeader<Trailing: View>: View {
    public let title: String
    public let subtitle: String?
    public let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(YomiFont.screenTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(YomiFont.screenSubtitle)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

public extension YomiScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

public struct YomiSectionHeader: View {
    public let title: String
    public let subtitle: String?
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        _ title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(YomiTheme.accentStrong)
            }
        }
    }
}

// MARK: - Surfaces

public struct YomiCard<Content: View>: View {
    public let content: Content
    public let padding: CGFloat

    public init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
    }
}

public struct YomiTag: View {
    public let text: String
    public let tint: Color
    public let filled: Bool

    public init(_ text: String, tint: Color = YomiTheme.textSecondary, filled: Bool = false) {
        self.text = text
        self.tint = tint
        self.filled = filled
    }

    public var body: some View {
        Text(text)
            .font(YomiFont.micro)
            .foregroundStyle(filled ? YomiTheme.background : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(filled ? tint : tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

public struct YomiStatBadge: View {
    public let icon: String
    public let value: String
    public let label: String
    public let tint: Color

    public init(icon: String, value: String, label: String, tint: Color = YomiTheme.accentStrong) {
        self.icon = icon
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(YomiFont.number)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)
                Text(label)
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Controls

public struct YomiSearchField: View {
    @Binding public var text: String
    public let placeholder: String
    public var onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Search",
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(focused ? YomiTheme.accentStrong : YomiTheme.textTertiary)

            TextField(placeholder, text: $text)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textPrimary)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { onSubmit?() }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(YomiTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(focused ? YomiTheme.accent.opacity(0.6) : YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct YomiSegmentedControl<Item: Hashable>: View {
    @Binding public var selection: Item
    public let items: [Item]
    public let title: (Item) -> String

    public init(selection: Binding<Item>, items: [Item], title: @escaping (Item) -> String) {
        self._selection = selection
        self.items = items
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item
                    }
                } label: {
                    Text(title(item))
                        .font(YomiFont.caption.weight(selection == item ? .semibold : .regular))
                        .foregroundStyle(selection == item ? YomiTheme.textPrimary : YomiTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Group {
                                if selection == item {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(YomiTheme.elevatedSurface)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(YomiTheme.sunkenSurface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

public struct YomiFilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let icon: String?
    public let action: () -> Void

    public init(title: String, isSelected: Bool, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(YomiFont.caption.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : YomiTheme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isSelected ? YomiTheme.elevatedSurface : YomiTheme.surface)
            .overlay(
                Capsule().stroke(isSelected ? YomiTheme.borderStrong : YomiTheme.border, lineWidth: 0.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

public struct YomiProgressBar: View {
    public let value: Double
    public let tint: Color
    public let height: CGFloat

    public init(value: Double, tint: Color = YomiTheme.accent, height: CGFloat = 2) {
        self.value = value
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * value)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Empty states

public struct YomiEmptyState: View {
    public let icon: String
    public let title: String
    public let message: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(YomiTheme.textSecondary)
                .frame(width: 60, height: 60)
                .background(YomiTheme.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(YomiTheme.border, lineWidth: 0.5))

            Text(title)
                .font(YomiFont.sectionTitle)
                .foregroundStyle(YomiTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(YomiPrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - Button styles

public struct YomiPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YomiFont.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(YomiTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

public struct YomiSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(YomiFont.caption.weight(.semibold))
            .foregroundStyle(YomiTheme.textPrimary)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

public struct YomiIconButtonStyle: ButtonStyle {
    public let size: CGFloat
    public let tint: Color

    public init(size: CGFloat = 36, tint: Color = YomiTheme.textPrimary) {
        self.size = size
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(YomiTheme.surface)
            .overlay(
                Circle().stroke(YomiTheme.border, lineWidth: 0.5)
            )
            .clipShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}


