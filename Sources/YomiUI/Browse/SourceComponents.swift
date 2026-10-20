import SwiftUI
import YomiCore
import YomiExtensions

/// Shared icon treatment for installed and remote sources.
public struct SourceIconView: View {
    public let name: String
    public let iconUrl: String?
    public let size: CGFloat

    public init(name: String, iconUrl: String?, size: CGFloat = 44) {
        self.name = name
        self.iconUrl = iconUrl
        self.size = size
    }

    public var body: some View {
        AsyncImage(url: URL(string: iconUrl ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    YomiTheme.elevatedSurface
                    Text(initials)
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Installed source list with safe, confirmed removal of community extensions.
public struct SourceManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var extensionManager = ExtensionManager.shared
    @State private var sourceToRemove: SourceManifest?
    @State private var errorMessage: String?

    public let onChanged: (() -> Void)?

    public init(onChanged: (() -> Void)? = nil) {
        self.onChanged = onChanged
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        YomiCard(padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(YomiTheme.accentStrong)
                                Text("Built-in connectors are permanent. Community extensions can be removed at any time.")
                                    .font(YomiFont.caption)
                                    .foregroundStyle(YomiTheme.textSecondary)
                                    .lineSpacing(2)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.danger)
                        }

                        VStack(spacing: 9) {
                            ForEach(sortedSources) { source in
                                sourceRow(source)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Installed Sources")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .confirmationDialog(
                "Remove \(sourceToRemove?.name ?? "source")?",
                isPresented: Binding(
                    get: { sourceToRemove != nil },
                    set: { if !$0 { sourceToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Source", role: .destructive) { removeSource() }
                Button("Cancel", role: .cancel) { sourceToRemove = nil }
            } message: {
                Text("Library titles and reading progress stay on device. You can reinstall this extension later.")
            }
        }
    }

    private var sortedSources: [SourceManifest] {
        extensionManager.installedSources
            .map { $0.manifest }
            .sorted { lhs, rhs in
                if isBuiltIn(lhs.id) != isBuiltIn(rhs.id) {
                    return isBuiltIn(lhs.id)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func sourceRow(_ manifest: SourceManifest) -> some View {
        HStack(spacing: 12) {
            SourceIconView(name: manifest.name, iconUrl: manifest.iconUrl, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(manifest.name)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)
                    if isBuiltIn(manifest.id) {
                        YomiTag("BUILT-IN", tint: YomiTheme.success)
                    }
                }
                HStack(spacing: 6) {
                    Text(manifest.lang.uppercased())
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                    Text(hostName(manifest.baseUrl))
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if !isBuiltIn(manifest.id) {
                Button(role: .destructive) {
                    sourceToRemove = manifest
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(YomiTheme.danger)
                        .frame(width: 34, height: 34)
                        .background(YomiTheme.danger.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(manifest.name)")
            }
        }
        .padding(11)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
    }

    private func removeSource() {
        guard let manifest = sourceToRemove else { return }
        do {
            try extensionManager.uninstallExtension(sourceId: manifest.id)
            sourceToRemove = nil
            onChanged?()
        } catch {
            errorMessage = error.localizedDescription
            sourceToRemove = nil
        }
    }
}

public func isBuiltInSource(_ sourceId: Int64) -> Bool {
    sourceId == MangaDexSource.sourceId || sourceId == MangaPillSource.sourceId
}

private func isBuiltIn(_ sourceId: Int64) -> Bool {
    isBuiltInSource(sourceId)
}

private func hostName(_ urlString: String) -> String {
    URL(string: urlString)?.host ?? urlString
}
