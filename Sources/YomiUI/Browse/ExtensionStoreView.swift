import SwiftUI
import YomiCore
import YomiDatabase
import YomiExtensions

/// Sleek, minimalist extension store for discovering, installing, and managing community sources.
public struct ExtensionStoreView: View {
    @State private var repos: [ExtensionRepo] = []
    @State private var availablePackages: [RemoteExtensionPackage] = []
    @State private var selectedLanguages: [String: String] = [:]
    @State private var installingPackageIds: Set<Int64> = []
    @State private var searchQuery: String = ""
    @State private var languageFilter: String = "all"
    @State private var storeFilter: StoreFilter = .all
    @State private var isLoading: Bool = true
    @State private var isRefreshing: Bool = false
    @State private var errorMessage: String?
    @State private var isShowingRepositories: Bool = false
    @State private var isShowingInstalledSources: Bool = false

    @State private var extensionManager = ExtensionManager.shared
    private let repoRepo = ExtensionRepoRepository()
    private let repoManager = RepoManager.shared
    public let embedded: Bool

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    private var groups: [ExtensionCatalogGroup] {
        ExtensionCatalog.group(availablePackages)
    }

    private var languages: [String] {
        let values = Set(availablePackages.map { $0.lang.lowercased() })
        return ["all"] + values.sorted()
    }

    private var filteredGroups: [ExtensionCatalogGroup] {
        var result = groups
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { group in
                group.name.localizedCaseInsensitiveContains(query)
                    || group.packageKey.localizedCaseInsensitiveContains(query)
                    || group.variants.contains {
                        $0.baseUrl.localizedCaseInsensitiveContains(query)
                            || $0.lang.localizedCaseInsensitiveContains(query)
                    }
            }
        }

        if languageFilter != "all" {
            result = result.filter { group in
                group.variants.contains { $0.lang.lowercased() == languageFilter.lowercased() }
            }
        }

        switch storeFilter {
        case .all:
            break
        case .installed:
            result = result.filter { hasAnyInstalledVariant($0) }
        case .updates:
            result = result.filter { isUpdateAvailable($0) }
        case .nsfw:
            result = result.filter(\.isNsfw)
        }
        return result
    }

    private var updateGroups: [ExtensionCatalogGroup] {
        groups.filter { isUpdateAvailable($0) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                topControls
                filtersBar

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if isLoading && availablePackages.isEmpty {
                    StoreSkeletonView()
                        .padding(.top, 8)
                } else if filteredGroups.isEmpty {
                    emptyState
                } else {
                    if (storeFilter == .all || storeFilter == .updates) && !updateGroups.isEmpty && searchQuery.isEmpty {
                        updatesSection
                    }
                    catalogSection
                }
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(YomiBackground(showsGlow: false))
        .navigationTitle(embedded ? "" : "Extensions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .yomiNavigationBarHidden(embedded)
        .sheet(isPresented: $isShowingRepositories) {
            ExtensionRepositorySheet {
                Task { await loadStore(forceRefresh: true) }
            }
        }
        .sheet(isPresented: $isShowingInstalledSources) {
            SourceManagementSheet {
                extensionManager.reloadInstalledSources()
            }
        }
        .task { await loadStore() }
    }

    // MARK: - Subviews

    private var topControls: some View {
        HStack(spacing: 8) {
            YomiSearchField(text: $searchQuery, placeholder: "Search extensions")

            Button {
                isShowingRepositories = true
            } label: {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YomiTheme.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(YomiTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(YomiTheme.border, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await loadStore(forceRefresh: true) }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .tint(YomiTheme.accentStrong)
                        .scaleEffect(0.65)
                        .frame(width: 42, height: 42)
                        .background(YomiTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(YomiTheme.border, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YomiTheme.textSecondary)
                        .frame(width: 42, height: 42)
                        .background(YomiTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(YomiTheme.border, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All languages") { languageFilter = "all" }
                ForEach(languages.filter { $0 != "all" }, id: \.self) { language in
                    Button(language.uppercased()) { languageFilter = language }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .bold))
                    Text(languageFilter == "all" ? "All" : languageFilter.uppercased())
                        .font(YomiFont.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(YomiTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(YomiTheme.surface)
                .overlay(Capsule().stroke(YomiTheme.border, lineWidth: 0.5))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StoreFilter.allCases, id: \.self) { option in
                        YomiFilterChip(
                            title: option.title,
                            isSelected: storeFilter == option,
                            icon: option.icon
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) { storeFilter = option }
                        }
                    }
                }
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            YomiSectionHeader("Updates Available", subtitle: "\(updateGroups.count) pending")
            VStack(spacing: 8) {
                ForEach(updateGroups) { group in
                    makeRow(for: group)
                }
            }
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            YomiSectionHeader(
                storeFilter == .installed ? "Installed Extensions" : "Available Extensions",
                subtitle: "\(filteredGroups.count) package\(filteredGroups.count == 1 ? "" : "s")"
            )

            VStack(spacing: 8) {
                ForEach(filteredGroups) { group in
                    makeRow(for: group)
                }
            }
        }
    }

    private func makeRow(for group: ExtensionCatalogGroup) -> some View {
        let variant = selectedVariant(for: group)
        let isInstalled = variant.map { isSourceInstalled($0.id) } ?? false
        let hasOther = hasAnyInstalledVariant(group) && !isInstalled
        let hasUpdate = isUpdateAvailable(group)
        let isInstalling = variant.map { installingPackageIds.contains($0.id) } ?? false

        return ExtensionRowView(
            group: group,
            selectedVariant: variant,
            isInstalled: isInstalled,
            hasOtherLanguageInstalled: hasOther,
            isUpdateAvailable: hasUpdate,
            isInstalling: isInstalling,
            onSelectLanguage: { selectedLanguages[group.packageKey] = $0 },
            onInstall: { install($0) },
            onManageInstalled: { isShowingInstalledSources = true }
        )
    }

    private var emptyState: some View {
        YomiEmptyState(
            icon: "puzzlepiece.extension",
            title: "No Extensions Found",
            message: searchQuery.isEmpty
                ? "Add a repository index URL or tap refresh to load sources."
                : "No extension matches '\(searchQuery)'. Try another search term.",
            actionTitle: searchQuery.isEmpty ? "Manage Repositories" : "Clear Search"
        ) {
            if searchQuery.isEmpty {
                isShowingRepositories = true
            } else {
                searchQuery = ""
                languageFilter = "all"
                storeFilter = .all
            }
        }
        .padding(.top, 24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(YomiTheme.warning)
            Text(message)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(YomiTheme.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - State Helpers

    private func selectedVariant(for group: ExtensionCatalogGroup) -> RemoteExtensionPackage? {
        guard let defaultVariant = group.defaultVariant else { return nil }
        if let language = selectedLanguages[group.packageKey],
           let chosen = group.variants.first(where: { $0.lang == language }) {
            return chosen
        }
        if let installed = group.variants.first(where: { isSourceInstalled($0.id) }) {
            return installed
        }
        return defaultVariant
    }

    private func isSourceInstalled(_ sourceId: Int64) -> Bool {
        extensionManager.installedSources.contains { $0.manifest.id == sourceId }
    }

    private func hasAnyInstalledVariant(_ group: ExtensionCatalogGroup) -> Bool {
        group.variants.contains { isSourceInstalled($0.id) }
    }

    private func isUpdateAvailable(_ group: ExtensionCatalogGroup) -> Bool {
        group.variants.contains { variant in
            guard let installed = extensionManager.installedSources.first(where: { $0.manifest.id == variant.id }) else {
                return false
            }
            return installed.manifest.version != variant.version
        }
    }

    // MARK: - Data Loading

    private func loadStore(forceRefresh: Bool = false) async {
        if availablePackages.isEmpty { isLoading = true }
        isRefreshing = true
        errorMessage = nil

        do {
            repos = try await repoRepo.getAllRepos()
            var collected: [Int64: RemoteExtensionPackage] = [:]
            var failures = 0

            await withTaskGroup(of: [RemoteExtensionPackage].self) { group in
                for repo in repos {
                    group.addTask {
                        do {
                            let index = try await RepoManager.shared.fetchRepoIndex(
                                from: repo.url,
                                forceRefresh: forceRefresh
                            )
                            return index.extensions
                        } catch {
                            return []
                        }
                    }
                }

                for await packages in group {
                    if packages.isEmpty { failures += 1 }
                    for package in packages {
                        collected[package.id] = package
                    }
                }
            }

            availablePackages = Array(collected.values)
            if availablePackages.isEmpty && !repos.isEmpty {
                errorMessage = "Could not reach repository servers. Check network connection."
            } else if failures > 0 {
                errorMessage = "\(failures) repository could not be loaded."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isRefreshing = false
    }

    private func install(_ package: RemoteExtensionPackage) {
        guard !installingPackageIds.contains(package.id) else { return }
        installingPackageIds.insert(package.id)

        Task {
            do {
                _ = try await repoManager.installExtension(package: package)
                extensionManager.reloadInstalledSources()
            } catch {
                errorMessage = "Install failed: \(error.localizedDescription)"
            }
            installingPackageIds.remove(package.id)
        }
    }
}
