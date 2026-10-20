import SwiftUI
import YomiCore
import YomiDatabase

public struct SourceExplorationView: View {
    public let source: any SourceProtocol

    @State private var mangas: [Manga] = []
    @State private var libraryKeys: Set<String> = []
    @State private var mode: SourceBrowseMode = .popular
    @State private var searchQuery: String = ""
    @State private var currentPage: Int = 1
    @State private var hasNextPage: Bool = true
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String?
    @State private var availableFilters: [Filter] = []
    @State private var appliedFilters: [Filter] = []
    @State private var isFilterSheetPresented: Bool = false
    @State private var loadGeneration: Int = 0
    @State private var loadTask: Task<Void, Never>?

    private let mangaRepo = MangaRepository()
    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 158), spacing: 12)]

    public init(source: any SourceProtocol) {
        self.source = source
    }

    private var hasActiveFilters: Bool {
        appliedFilters.contains { !$0.isDefault }
    }

    private var hasQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ZStack {
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    sourceHero
                    searchAndMode

                    if isLoading && mangas.isEmpty {
                        skeletonGrid
                    } else if let errorMessage, mangas.isEmpty {
                        errorState(errorMessage)
                    } else if mangas.isEmpty {
                        YomiEmptyState(
                            icon: "magnifyingglass",
                            title: "No Titles Found",
                            message: hasQuery
                                ? "No titles matched this search inside \(source.manifest.name)."
                                : "This source returned an empty catalog. Pull to refresh or try another mode.",
                            actionTitle: "Retry",
                            action: { reload() }
                        )
                    } else {
                        resultsGrid

                        if hasNextPage {
                            loadMoreButton
                        }
                    }
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .refreshable { reload() }
        }
        .navigationTitle(source.manifest.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            if !availableFilters.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isFilterSheetPresented = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasActiveFilters ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            SourceFilterSheet(
                currentFilters: appliedFilters,
                defaultFilters: availableFilters,
                onApply: { updated in
                    appliedFilters = updated
                    reload()
                },
                onReset: {
                    appliedFilters = availableFilters
                    reload()
                }
            )
        }
        .onAppear {
            loadLibraryKeys()
            if availableFilters.isEmpty {
                let filters = source.getFilters()
                availableFilters = filters
                appliedFilters = filters
            }
            if mangas.isEmpty { reload() }
        }
        .onDisappear {
            loadTask?.cancel()
            loadGeneration += 1
            isLoading = false
            isLoadingMore = false
        }
    }

    // MARK: - Hero

    private var sourceHero: some View {
        YomiCard(padding: 16) {
            HStack(spacing: 13) {
                SourceIconView(
                    name: source.manifest.name,
                    iconUrl: source.manifest.iconUrl,
                    size: 54
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(source.manifest.name)
                            .font(YomiFont.sectionTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                            .lineLimit(1)
                        if source.manifest.isNsfw {
                            YomiTag("18+", tint: YomiTheme.danger)
                        }
                    }
                    Text(URL(string: source.manifest.baseUrl)?.host ?? source.manifest.baseUrl)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        YomiTag(source.manifest.lang.uppercased(), tint: YomiTheme.accentStrong)
                        YomiTag("v\(source.manifest.version)", tint: YomiTheme.textSecondary)
                        if isBuiltInSource(source.manifest.id) {
                            YomiTag("NATIVE", tint: YomiTheme.success)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Search and modes

    private var searchAndMode: some View {
        VStack(spacing: 10) {
            YomiSearchField(
                text: $searchQuery,
                placeholder: "Search inside \(source.manifest.name)",
                onSubmit: { reload() }
            )
            .onChange(of: searchQuery) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reload()
                }
            }

            HStack(spacing: 8) {
                if source.manifest.supportsLatest {
                    YomiSegmentedControl(
                        selection: $mode,
                        items: SourceBrowseMode.allCases,
                        title: { $0.title }
                    )
                    .onChange(of: mode) { _, _ in
                        if !hasQuery { reload() }
                    }
                } else {
                    HStack {
                        YomiTag("POPULAR", tint: YomiTheme.accentStrong)
                        Spacer()
                        if hasActiveFilters {
                            YomiTag("FILTERED", tint: YomiTheme.warning)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Results

    private var resultsGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(mangas, id: \.stableId) { manga in
                NavigationLink {
                    MangaDetailView(manga: resolvedManga(manga))
                } label: {
                    MangaGridCard(
                        manga: resolvedManga(manga),
                        showsLibraryBadge: true
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Task { await toggleLibrary(manga) }
                    } label: {
                        Label(
                            resolvedManga(manga).inLibrary ? "Remove from Library" : "Add to Library",
                            systemImage: resolvedManga(manga).inLibrary ? "trash" : "heart"
                        )
                    }
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            fetchNextPage()
        } label: {
            HStack(spacing: 8) {
                if isLoadingMore {
                    ProgressView().tint(YomiTheme.textPrimary).scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.down.circle")
                }
                Text(isLoadingMore ? "Loading" : "Load More")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(YomiSecondaryButtonStyle())
        .disabled(isLoading || isLoadingMore)
        .onAppear {
            fetchNextPage()
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .fill(YomiTheme.surface)
                    .aspectRatio(11.0 / 16.0, contentMode: .fit)
                    .overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.7))
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        YomiCard(padding: 18) {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(YomiTheme.warning)
                Text("Could Not Load Source")
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                Text(message)
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Button("Retry", action: { reload() })
                    .buttonStyle(YomiPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Data

    private func resolvedManga(_ manga: Manga) -> Manga {
        var copy = manga
        if libraryKeys.contains("\(manga.sourceId)|\(manga.url)") {
            copy.inLibrary = true
        }
        return copy
    }

    private func loadLibraryKeys() {
        Task {
            guard let library = try? await mangaRepo.getLibraryMangas() else { return }
            await MainActor.run {
                libraryKeys = Set(library.map { "\($0.sourceId)|\($0.url)" })
            }
        }
    }

    private func toggleLibrary(_ manga: Manga) async {
        let key = "\(manga.sourceId)|\(manga.url)"
        let isInLibrary = libraryKeys.contains(key)
        do {
            if isInLibrary {
                // Catalog results do not carry a database id. Resolve the saved row by
                // source/url before mutating it, otherwise removal silently does nothing.
                let saved = try await mangaRepo.getManga(sourceId: manga.sourceId, url: manga.url)
                if let id = manga.id ?? saved?.id {
                    try await mangaRepo.setInLibrary(mangaId: id, inLibrary: false)
                }
            } else {
                var copy = manga
                copy.inLibrary = true
                let saved = try await mangaRepo.upsert(copy)
                if let id = saved.id {
                    try await mangaRepo.setInLibrary(mangaId: id, inLibrary: true)
                }
            }

            await MainActor.run {
                if isInLibrary {
                    libraryKeys.remove(key)
                } else {
                    libraryKeys.insert(key)
                }
                if let index = mangas.firstIndex(where: { $0.stableId == manga.stableId }) {
                    mangas[index].inLibrary = !isInLibrary
                }
            }
        } catch {
            print("[SourceExploration] Library toggle failed: \(error)")
        }
    }

    private func reload() {
        loadTask?.cancel()
        loadGeneration += 1
        currentPage = 1
        mangas = []
        errorMessage = nil
        hasNextPage = true
        isLoading = false
        isLoadingMore = false
        fetchNextPage()
    }

    private func fetchNextPage() {
        guard !isLoading, !isLoadingMore, hasNextPage else { return }
        if currentPage == 1 {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        let generation = loadGeneration
        let pageToLoad = currentPage
        let query = searchQuery
        let filters = appliedFilters
        let requestedMode = mode
        let isSearchRequest = hasQuery || hasActiveFilters

        loadTask = Task {
            do {
                let result: MangaPageResult
                if isSearchRequest {
                    result = try await source.searchManga(
                        query: query,
                        filters: filters,
                        page: pageToLoad
                    )
                } else if requestedMode == .popular {
                    result = try await source.getPopularManga(page: pageToLoad)
                } else {
                    result = try await source.getLatestUpdates(page: pageToLoad)
                }

                await MainActor.run {
                    // Ignore responses from a query, mode, or reload that has since been replaced.
                    guard generation == loadGeneration else { return }
                    let existing = Set(mangas.map(\.stableId))
                    mangas.append(contentsOf: result.mangas.filter { !existing.contains($0.stableId) })
                    hasNextPage = result.hasNextPage
                    currentPage += 1
                    isLoading = false
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    guard generation == loadGeneration else { return }
                    errorMessage = error.localizedDescription
                    isLoading = false
                    isLoadingMore = false
                }
            }
        }
    }
}

enum SourceBrowseMode: String, CaseIterable {
    case popular = "Popular"
    case latest = "Latest"

    var title: String { rawValue }
}
