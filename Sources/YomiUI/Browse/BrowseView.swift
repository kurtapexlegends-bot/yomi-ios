import SwiftUI
import YomiCore
import YomiExtensions
import YomiDatabase

enum BrowseSegment: String, CaseIterable {
    case sources = "Sources"
    case extensions = "Extensions"
}

public struct BrowseView: View {
    @State private var selectedSegment: BrowseSegment = .sources
    @State private var extensionManager = ExtensionManager.shared
    @State private var isShowingSourceManagement: Bool = false
    @State private var sourceToRemove: SourceManifest?
    @State private var removalError: String?

    public init() {}

    private var sources: [any SourceProtocol] {
        extensionManager.installedSources
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground()

                VStack(spacing: 0) {
                    header
                    segmentControl

                    if selectedSegment == .sources {
                        SourcesCatalogView(
                            sources: sources,
                            onManageSources: { isShowingSourceManagement = true },
                            onOpenStore: { selectedSegment = .extensions },
                            onRemoveSource: { manifest in sourceToRemove = manifest }
                        )
                        .transition(.opacity)
                    } else {
                        ExtensionStoreView(embedded: true)
                            .transition(.opacity)
                    }
                }
            }
            .yomiNavigationBarHidden()
            .sheet(isPresented: $isShowingSourceManagement) {
                SourceManagementSheet {
                    extensionManager.reloadInstalledSources()
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
                Text("The extension will be uninstalled. Titles already in your library and their reading progress are kept.")
            }
            .alert(
                "Could Not Remove Source",
                isPresented: Binding(
                    get: { removalError != nil },
                    set: { if !$0 { removalError = nil } }
                )
            ) {
                Button("OK") { removalError = nil }
            } message: {
                Text(removalError ?? "")
            }
        }
    }

    private var header: some View {
        YomiScreenHeader(
            title: "Browse",
            subtitle: subtitle
        ) {
            Button {
                isShowingSourceManagement = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(YomiIconButtonStyle())
        }
        .padding(.horizontal, YomiTheme.contentPadding)
        .padding(.top, 14)
    }

    private var subtitle: String {
        if selectedSegment == .extensions {
            return "Discover and manage source extensions"
        }
        let languages = Set(sources.map { $0.manifest.lang }).count
        return "\(sources.count) sources · \(languages) languages"
    }

    private var segmentControl: some View {
        YomiSegmentedControl(
            selection: $selectedSegment,
            items: BrowseSegment.allCases,
            title: { $0.rawValue }
        )
        .padding(.horizontal, YomiTheme.contentPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func removeSource() {
        guard let manifest = sourceToRemove else { return }
        do {
            try extensionManager.uninstallExtension(sourceId: manifest.id)
            sourceToRemove = nil
        } catch {
            removalError = error.localizedDescription
            sourceToRemove = nil
        }
    }
}

// MARK: - Sources list

private struct SourcesCatalogView: View {
    let sources: [any SourceProtocol]
    let onManageSources: () -> Void
    let onOpenStore: () -> Void
    let onRemoveSource: (SourceManifest) -> Void

    @State private var searchQuery: String = ""
    @State private var sourceFilter: SourceFilter = .all

    private let privacyManager = PrivacyManager.shared

    private var filteredSources: [any SourceProtocol] {
        var items = sources

        switch sourceFilter {
        case .all:
            break
        case .builtIn:
            items = items.filter { isBuiltInSource($0.manifest.id) }
        case .community:
            items = items.filter { !isBuiltInSource($0.manifest.id) }
        case .nsfw:
            items = items.filter { $0.manifest.isNsfw }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                $0.manifest.name.localizedCaseInsensitiveContains(query)
                    || $0.manifest.baseUrl.localizedCaseInsensitiveContains(query)
            }
        }

        return items.sorted {
            if isBuiltInSource($0.manifest.id) != isBuiltInSource($1.manifest.id) {
                return isBuiltInSource($0.manifest.id)
            }
            return $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending
        }
    }

    private var builtInSources: [any SourceProtocol] {
        filteredSources.filter { isBuiltInSource($0.manifest.id) }
    }

    private var communitySources: [any SourceProtocol] {
        filteredSources.filter { !isBuiltInSource($0.manifest.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                searchCard
                filters

                if filteredSources.isEmpty {
                    YomiEmptyState(
                        icon: "globe.badge.chevron.backward",
                        title: searchQuery.isEmpty ? "No Sources Here" : "No Matches",
                        message: searchQuery.isEmpty
                            ? "Install an extension from the Extension Store to start browsing."
                            : "Try another source name or clear the active filter.",
                        actionTitle: searchQuery.isEmpty ? "Open Extension Store" : "Clear Search"
                    ) {
                        if searchQuery.isEmpty {
                            onOpenStore()
                        } else {
                            searchQuery = ""
                            sourceFilter = .all
                        }
                    }
                } else {
                    if !builtInSources.isEmpty {
                        sourceSection(title: "Built-in", subtitle: "Always available", sources: builtInSources)
                    }
                    if !communitySources.isEmpty {
                        sourceSection(
                            title: "Community",
                            subtitle: "\(communitySources.count) installed extensions",
                            sources: communitySources
                        )
                    }
                }
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
    }

    private var searchCard: some View {
        NavigationLink {
            GlobalSearchView(sources: sources)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(YomiTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search every source")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text("Find a title across all installed extensions")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(YomiTheme.accentStrong)
            }
            .padding(14)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var filters: some View {
        VStack(spacing: 9) {
            YomiSearchField(text: $searchQuery, placeholder: "Search installed sources")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(SourceFilter.allCases, id: \.self) { option in
                        YomiFilterChip(
                            title: option.title,
                            isSelected: sourceFilter == option,
                            icon: option.icon
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { sourceFilter = option }
                        }
                    }
                }
            }
        }
    }

    private func sourceSection(title: String, subtitle: String, sources: [any SourceProtocol]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            YomiSectionHeader(title, subtitle: subtitle)

            VStack(spacing: 8) {
                ForEach(sources.map(SourceBox.init)) { box in
                    sourceRow(box.source)
                }
            }
        }
    }

    private func sourceRow(_ source: any SourceProtocol) -> some View {
        let manifest = source.manifest
        return NavigationLink {
            SourceExplorationView(source: source)
        } label: {
            HStack(spacing: 12) {
                SourceIconView(name: manifest.name, iconUrl: manifest.iconUrl, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(manifest.name)
                            .font(YomiFont.cardTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                            .lineLimit(1)
                        if manifest.isNsfw {
                            YomiTag("18+", tint: YomiTheme.danger)
                        }
                        if isBuiltInSource(manifest.id) {
                            YomiTag("NATIVE", tint: YomiTheme.success)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(manifest.lang.uppercased())
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                        Text(URL(string: manifest.baseUrl)?.host ?? manifest.baseUrl)
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(YomiTheme.textTertiary)
            }
            .padding(12)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isBuiltInSource(manifest.id) {
                Button(role: .destructive) {
                    onRemoveSource(manifest)
                } label: {
                    Label("Remove Source", systemImage: "trash")
                }
            }
            Button {
                onManageSources()
            } label: {
                Label("Manage Sources", systemImage: "slider.horizontal.3")
            }
        }
    }
}

enum SourceFilter: String, CaseIterable {
    case all = "All"
    case builtIn = "Built-in"
    case community = "Community"
    case nsfw = "18+"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "globe"
        case .builtIn: return "checkmark.seal.fill"
        case .community: return "puzzlepiece.extension.fill"
        case .nsfw: return "exclamationmark.triangle.fill"
        }
    }
}

private struct SourceBox: Identifiable {
    let source: any SourceProtocol
    var id: Int64 { source.manifest.id }
}
