import SwiftUI
import YomiCore
import YomiDatabase
import YomiExtensions

/// Redesigned extension store: installed sources, repositories, language variants, and search
/// are first-class instead of being buried in a flat list.
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
                    || group.variants.contains { $0.baseUrl.localizedCaseInsensitiveContains(query) }
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

    private var installedCommunityCount: Int {
        extensionManager.installedSources.filter { !isBuiltInSource($0.manifest.id) }.count
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                storeHeader
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                installedCard
                repositoriesCard
                controls
                catalogSection
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(YomiBackground())
        .navigationTitle(embedded ? "" : "Extensions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar(embedded ? .hidden : .visible, for: .navigationBar)
        .sheet(isPresented: $isShowingRepositories) {
            ExtensionRepositorySheet {
                Task { await loadStore(forceRefresh: true) }
            }
        }
        .sheet(isPresented: $isShowingInstalledSources) {
            SourceManagementSheet {
                // @Observable manager updates the store immediately.
                extensionManager.reloadInstalledSources()
            }
        }
        .alert(
            "Extension Store",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await loadStore() }
    }

    // MARK: - Header

    private var storeHeader: some View {
        YomiCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(YomiTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        YomiEyebrow("EXTENSION STORE")
                        Text("More places to read")
                            .font(YomiFont.sectionTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("\(groups.count) extension packages · \(languages.count - 1) languages")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    YomiTag("\(installedCommunityCount) installed", tint: YomiTheme.success)
                    YomiTag("\(repos.count) repositories", tint: YomiTheme.accentStrong)
                    Spacer()
                    Button {
                        Task { await loadStore(forceRefresh: true) }
                    } label: {
                        if isRefreshing {
                            ProgressView().tint(YomiTheme.textPrimary).scaleEffect(0.65)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(YomiSecondaryButtonStyle())
                    .disabled(isRefreshing)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(YomiTheme.warning)
            Text(message)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(YomiTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Installed sources

    private var installedCard: some View {
        YomiCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed sources")
                            .font(YomiFont.cardTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("Built-in connectors and community extensions")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                    Text("\(extensionManager.installedSources.count)")
                        .font(YomiFont.number)
                        .foregroundStyle(YomiTheme.accentStrong)
                }

                HStack(spacing: -8) {
                    ForEach(extensionManager.installedSources.prefix(6).map { $0.manifest }) { manifest in
                        SourceIconView(
                            name: manifest.name,
                            iconUrl: manifest.iconUrl,
                            size: 32
                        )
                        .overlay(Circle().stroke(YomiTheme.surface, lineWidth: 2))
                    }
                    Spacer()
                    Button {
                        isShowingInstalledSources = true
                    } label: {
                        Label("Manage", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(YomiSecondaryButtonStyle())
                }
            }
        }
    }

    private var repositoriesCard: some View {
        YomiCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YomiTheme.warning)
                    .frame(width: 38, height: 38)
                    .background(YomiTheme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Repositories")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(repos.first?.name ?? "Keiyoushi")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    isShowingRepositories = true
                } label: {
                    Text("Manage")
                }
                .buttonStyle(YomiSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            YomiSearchField(text: $searchQuery, placeholder: "Search extensions and languages")

            HStack(spacing: 8) {
                Menu {
                    Button("All languages") { languageFilter = "all" }
                    ForEach(languages.filter { $0 != "all" }, id: \.self) { language in
                        Button(language.uppercased()) { languageFilter = language }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .bold))
                        Text(languageFilter == "all" ? "All languages" : languageFilter.uppercased())
                            .font(YomiFont.caption.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(YomiTheme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(YomiTheme.surface)
                    .overlay(Capsule().stroke(YomiTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(StoreFilter.allCases, id: \.self) { option in
                            YomiFilterChip(
                                title: option.title,
                                isSelected: storeFilter == option,
                                icon: option.icon
                            ) {
                                withAnimation(.easeOut(duration: 0.18)) { storeFilter = option }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader(
                "Available Extensions",
                subtitle: "\(filteredGroups.count) result\(filteredGroups.count == 1 ? "" : "s")"
            )

            if isLoading {
                VStack(spacing: 9) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                            .fill(YomiTheme.surface)
                            .frame(height: 88)
                    }
                }
            } else if filteredGroups.isEmpty {
                YomiEmptyState(
                    icon: "puzzlepiece.extension",
                    title: "No Extensions Found",
                    message: searchQuery.isEmpty
                        ? "Add a repository or refresh the catalog to discover new sources."
                        : "Try a different extension name, language, or filter.",
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
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(filteredGroups) { group in
                        extensionRow(group)
                    }
                }
            }
        }
    }

    private func extensionRow(_ group: ExtensionCatalogGroup) -> some View {
        let variant = selectedVariant(for: group)
        let selectedInstalled = variant.map { isSourceInstalled($0.id) } ?? false
        let anyInstalled = hasAnyInstalledVariant(group)
        let updateAvailable = isUpdateAvailable(group)

        return HStack(alignment: .top, spacing: 12) {
            SourceIconView(name: group.name, iconUrl: group.iconUrl, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)
                    if group.isNsfw {
                        YomiTag("18+", tint: YomiTheme.danger)
                    }
                    if updateAvailable {
                        YomiTag("UPDATE", tint: YomiTheme.warning)
                    }
                }

                Text(variantHost(variant))
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("v\(variant?.version ?? "—")")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                    if group.variantCount > 1 {
                        Text("· \(group.variantCount) languages")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                    }
                    if anyInstalled && !selectedInstalled {
                        Text("· installed in another language")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.success)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 2)

            VStack(alignment: .trailing, spacing: 7) {
                if group.variantCount > 1 {
                    Menu {
                        ForEach(group.variants) { option in
                            Button {
                                selectedLanguages[group.packageKey] = option.lang
                            } label: {
                                if option.lang == variant?.lang {
                                    Label(option.lang.uppercased(), systemImage: "checkmark")
                                } else {
                                    Text(option.lang.uppercased())
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text((variant?.lang ?? "en").uppercased())
                                .font(YomiFont.micro)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(YomiTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(YomiTheme.elevatedSurface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if selectedInstalled {
                    Label("Installed", systemImage: "checkmark")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.success)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(YomiTheme.success.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Button {
                        install(variant)
                    } label: {
                        if let id = variant?.id, installingPackageIds.contains(id) {
                            ProgressView().tint(.white).scaleEffect(0.6)
                        } else {
                            Text(updateAvailable ? "Update" : anyInstalled ? "Add" : "Install")
                        }
                    }
                    .buttonStyle(YomiPrimaryButtonStyle())
                    .disabled(variant == nil || installingPackageIds.contains(variant?.id ?? -1))
                }
            }
        }
        .padding(12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        .contextMenu {
            if let variant {
                Button {
                    install(variant)
                } label: {
                    Label("Install \(variant.lang.uppercased())", systemImage: "arrow.down.circle")
                }
            }
            if anyInstalled {
                Button(role: .destructive) {
                    isShowingInstalledSources = true
                } label: {
                    Label("Manage Installed Sources", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - State helpers

    private func selectedVariant(for group: ExtensionCatalogGroup) -> RemoteExtensionPackage? {
        guard let defaultVariant = group.defaultVariant else { return nil }
        guard let language = selectedLanguages[group.packageKey] else { return defaultVariant }
        return group.variants.first { $0.lang == language } ?? defaultVariant
    }

    private func isSourceInstalled(_ sourceId: Int64) -> Bool {
        extensionManager.installedSources.contains { $0.manifest.id == sourceId }
    }

    private func hasAnyInstalledVariant(_ group: ExtensionCatalogGroup) -> Bool {
        group.variants.contains { isSourceInstalled($0.id) }
    }

    private func isUpdateAvailable(_ group: ExtensionCatalogGroup) -> Bool {
        let variant = selectedVariant(for: group)
        guard let variant,
              let installed = extensionManager.installedSources.first(where: { $0.manifest.id == variant.id }) else {
            return false
        }
        return installed.manifest.version != variant.version
    }

    private func variantHost(_ variant: RemoteExtensionPackage?) -> String {
        guard let variant, let host = URL(string: variant.baseUrl)?.host else {
            return variant?.baseUrl ?? "Community source"
        }
        return host
    }

    // MARK: - Actions

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
            if availablePackages.isEmpty {
                errorMessage = "No repository catalog could be loaded. Check your connection and repository URLs."
            } else if failures > 0 {
                errorMessage = "\(failures) repository could not be fully loaded. Showing the extensions that were available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isRefreshing = false
    }

    private func install(_ package: RemoteExtensionPackage?) {
        guard let package, !installingPackageIds.contains(package.id) else { return }
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

enum StoreFilter: String, CaseIterable {
    case all = "All"
    case installed = "Installed"
    case updates = "Updates"
    case nsfw = "18+"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .installed: return "checkmark.circle.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .nsfw: return "exclamationmark.triangle.fill"
        }
    }
}
