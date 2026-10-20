import SwiftUI
import YomiCore
import YomiDatabase
import YomiExtensions

public enum StoreFilter: String, CaseIterable, Sendable {
    case all = "All"
    case installed = "Installed"
    case updates = "Updates"
    case nsfw = "18+"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .installed: return "checkmark.circle"
        case .updates: return "arrow.triangle.2.circlepath"
        case .nsfw: return "exclamationmark.shield"
        }
    }
}

/// Clean, high-signal row for an extension package in the catalog.
public struct ExtensionRowView: View {
    public let group: ExtensionCatalogGroup
    public let selectedVariant: RemoteExtensionPackage?
    public let isInstalled: Bool
    public let hasOtherLanguageInstalled: Bool
    public let isUpdateAvailable: Bool
    public let isInstalling: Bool
    public let onSelectLanguage: (String) -> Void
    public let onInstall: (RemoteExtensionPackage) -> Void
    public let onManageInstalled: () -> Void

    public init(
        group: ExtensionCatalogGroup,
        selectedVariant: RemoteExtensionPackage?,
        isInstalled: Bool,
        hasOtherLanguageInstalled: Bool,
        isUpdateAvailable: Bool,
        isInstalling: Bool,
        onSelectLanguage: @escaping (String) -> Void,
        onInstall: @escaping (RemoteExtensionPackage) -> Void,
        onManageInstalled: @escaping () -> Void
    ) {
        self.group = group
        self.selectedVariant = selectedVariant
        self.isInstalled = isInstalled
        self.hasOtherLanguageInstalled = hasOtherLanguageInstalled
        self.isUpdateAvailable = isUpdateAvailable
        self.isInstalling = isInstalling
        self.onSelectLanguage = onSelectLanguage
        self.onInstall = onInstall
        self.onManageInstalled = onManageInstalled
    }

    private var host: String {
        guard let variant = selectedVariant, let url = URL(string: variant.baseUrl), let host = url.host else {
            return selectedVariant?.baseUrl ?? "Community source"
        }
        return host
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SourceIconView(name: group.name, iconUrl: group.iconUrl, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)

                    if group.isNsfw {
                        YomiTag("18+", tint: YomiTheme.danger)
                    }
                    if isUpdateAvailable {
                        YomiTag("UPDATE", tint: YomiTheme.warning)
                    }
                }

                Text(host)
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("v\(selectedVariant?.version ?? "1.0.0")")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)

                    if group.variantCount > 1 {
                        Text("· \(group.variantCount) langs")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                    }

                    if hasOtherLanguageInstalled && !isInstalled {
                        Text("· other lang installed")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.success)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                if group.variantCount > 1 {
                    languageMenu
                }
                actionButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if let selectedVariant {
                Button {
                    onInstall(selectedVariant)
                } label: {
                    Label("Install \(selectedVariant.lang.uppercased())", systemImage: "arrow.down.circle")
                }
            }
            if isInstalled || hasOtherLanguageInstalled {
                Button(role: .destructive) {
                    onManageInstalled()
                } label: {
                    Label("Manage Installed Sources", systemImage: "trash")
                }
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(group.variants) { option in
                Button {
                    onSelectLanguage(option.lang)
                } label: {
                    if option.lang == selectedVariant?.lang {
                        Label(option.lang.uppercased(), systemImage: "checkmark")
                    } else {
                        Text(option.lang.uppercased())
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text((selectedVariant?.lang ?? "en").uppercased())
                    .font(YomiFont.micro.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(YomiTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(YomiTheme.elevatedSurface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isInstalling {
            ProgressView()
                .tint(YomiTheme.accentStrong)
                .scaleEffect(0.7)
                .frame(width: 58, height: 28)
                .background(YomiTheme.elevatedSurface)
                .clipShape(Capsule())
        } else if isUpdateAvailable {
            Button {
                if let selectedVariant { onInstall(selectedVariant) }
            } label: {
                Text("Update")
                    .font(YomiFont.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(YomiTheme.warning)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if isInstalled {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Installed")
                    .font(YomiFont.micro.weight(.semibold))
            }
            .foregroundStyle(YomiTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(YomiTheme.elevatedSurface)
            .clipShape(Capsule())
        } else {
            Button {
                if let selectedVariant { onInstall(selectedVariant) }
            } label: {
                Text(hasOtherLanguageInstalled ? "Add" : "Get")
                    .font(YomiFont.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(YomiTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedVariant == nil)
        }
    }
}

/// Shimmering skeleton cards while repository indexes are loading.
public struct StoreSkeletonView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(YomiTheme.surface)
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(YomiTheme.border, lineWidth: 0.5)
                    )
            }
        }
    }
}
