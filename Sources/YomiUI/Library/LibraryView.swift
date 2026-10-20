import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload

/// Minimalist, cover-forward personal manga library on True OLED Black canvas.
public struct LibraryView: View {
    @State private var mangas: [Manga] = []
    @State private var categories: [YomiCategory] = []
    @State private var categoryCounts: [Int64: Int] = [:]
    @State private var totalLibraryCount: Int = 0
    @State private var selectedCategoryId: Int64? = nil
    @State private var searchQuery: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var progressByManga: [Int64: MangaChapterProgress] = [:]
    @State private var lastReadByManga: [Int64: Date] = [:]
    @State private var downloadCounts: [Int64: Int] = [:]

    @State private var readerRequest: ReaderRequest?
    @State private var mangaToRemove: Manga?
    @State private var isConfirmingRemoval: Bool = false
    @State private var isShowingCategoryManager: Bool = false
    @State private var isShowingFilters: Bool = false

    @AppStorage("yomi.library.layout") private var layoutRaw: String = "grid"
    @AppStorage("yomi.library.sort") private var sortRaw: String = LibrarySort.title.rawValue
    @AppStorage("yomi.library.filter") private var filterRaw: String = LibraryFilter.all.rawValue

    private let mangaRepo = MangaRepository()
    private let categoryRepo = CategoryRepository()
    private let chapterRepo = ChapterRepository()
    private let historyRepo = HistoryRepository()
    private let downloadManager = DownloadManager.shared
    private let privacyManager = PrivacyManager.shared
    private let biometricManager = BiometricSecurityManager.shared
    private let router = AppRouter.shared

    private let gridColumns = [
        GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12)
    ]

    public init() {}

    private var sort: LibrarySort {
        LibrarySort(rawValue: sortRaw) ?? .title
    }

    private var filter: LibraryFilter {
        LibraryFilter(rawValue: filterRaw) ?? .all
    }

    private var isListLayout: Bool {
        layoutRaw == "list"
    }

    private var selectedCategory: YomiCategory? {
        categories.first { $0.id == selectedCategoryId }
    }

    private var unreadTotal: Int {
        progressByManga.values.reduce(0) { $0 + $1.unreadChapters }
    }

    private var displayedMangas: [Manga] {
        var items = mangas

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter { manga in
                manga.title.localizedCaseInsensitiveContains(query)
                    || (manga.author?.localizedCaseInsensitiveContains(query) ?? false)
                    || (manga.description?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        switch filter {
        case .all:
            break
        case .unread:
            items = items.filter { (progressByManga[$0.id ?? -1]?.unreadChapters ?? 0) > 0 }
        case .downloaded:
            items = items.filter { (downloadCounts[$0.id ?? -1] ?? 0) > 0 }
        case .completed:
            items = items.filter { progressByManga[$0.id ?? -1]?.isCompleted == true }
        }

        switch sort {
        case .title:
            items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyAdded:
            items.sort { $0.dateAdded > $1.dateAdded }
        case .lastUpdated:
            items.sort { $0.lastUpdate > $1.lastUpdate }
        case .lastRead:
            items.sort {
                (lastReadByManga[$0.id ?? -1] ?? .distantPast) > (lastReadByManga[$1.id ?? -1] ?? .distantPast)
            }
        case .mostUnread:
            items.sort {
                (progressByManga[$0.id ?? -1]?.unreadChapters ?? 0) > (progressByManga[$1.id ?? -1]?.unreadChapters ?? 0)
            }
        }

        return items
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                VStack(spacing: 0) {
                    categoryBar

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if privacyManager.isIncognitoMode {
                                incognitoNotice
                            }

                            if isLoading && mangas.isEmpty {
                                loadingGrid
                            } else if displayedMangas.isEmpty {
                                emptyState
                            } else if isListLayout {
                                listContent
                            } else {
                                gridContent
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(YomiFont.caption)
                                    .foregroundStyle(YomiTheme.danger)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, YomiTheme.contentPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await loadLibrary() }
                }
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if unreadTotal > 0 {
                        Text("\(unreadTotal) unread")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(filter == .all ? YomiTheme.textSecondary : YomiTheme.accentStrong)
                    }

                    Button {
                        layoutRaw = isListLayout ? "grid" : "list"
                    } label: {
                        Image(systemName: isListLayout ? "square.grid.2x2" : "list.bullet")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search titles or authors")
            .sheet(isPresented: $isShowingCategoryManager) {
                NavigationStack { CategoryManagerView() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingFilters) {
                LibraryFilterSheet(
                    sort: sort,
                    filter: filter,
                    onSelectSort: { sortRaw = $0.rawValue },
                    onSelectFilter: { filterRaw = $0.rawValue }
                )
                .presentationDetents([.medium])
            }
            .yomiFullScreenCover(item: $readerRequest, onDismiss: {
                Task { await loadLibrary(showsSpinner: false) }
            }) { request in
                ReaderContainerView(manga: request.manga, chapter: request.chapter)
            }
            .confirmationDialog(
                "Remove \(mangaToRemove?.title ?? "title") from library?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove from Library", role: .destructive) { removeFromLibrary() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The title stays available in its source. Your reading history is kept.")
            }
            .task { await loadLibrary() }
            .onChange(of: selectedCategoryId) { _, _ in
                Task { await loadLibrary(showsSpinner: false) }
            }
        }
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(
                    title: "All",
                    count: totalLibraryCount,
                    isSelected: selectedCategoryId == nil
                ) {
                    selectCategory(nil)
                }

                ForEach(categories) { category in
                    categoryPill(
                        title: category.name,
                        count: category.id.flatMap { categoryCounts[$0] },
                        isSelected: selectedCategoryId == category.id
                    ) {
                        selectCategory(category)
                    }
                }

                Button {
                    isShowingCategoryManager = true
                } label: {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(YomiTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.vertical, 8)
        }
        .background(YomiTheme.pureBlack)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
    }

    private func categoryPill(title: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(YomiFont.caption.weight(isSelected ? .semibold : .regular))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(YomiFont.micro)
                        .foregroundStyle(isSelected ? YomiTheme.accentStrong : YomiTheme.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? .white : YomiTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? YomiTheme.elevatedSurface : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? YomiTheme.borderStrong : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var incognitoNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .medium))
            Text("Incognito mode active · History and tracker writes paused")
                .font(YomiFont.caption)
        }
        .foregroundStyle(YomiTheme.accentStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YomiTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Content Layouts

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
            ForEach(displayedMangas) { manga in
                NavigationLink {
                    MangaDetailView(manga: manga)
                } label: {
                    MangaGridCard(
                        manga: manga,
                        unreadCount: progressByManga[manga.id ?? -1]?.unreadChapters ?? 0,
                        progress: progressByManga[manga.id ?? -1]?.fraction ?? 0,
                        showsLibraryBadge: false
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { contextMenu(for: manga) }
            }
        }
    }

    private var listContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(displayedMangas) { manga in
                NavigationLink {
                    MangaDetailView(manga: manga)
                } label: {
                    MangaListRow(
                        manga: manga,
                        unreadCount: progressByManga[manga.id ?? -1]?.unreadChapters ?? 0,
                        progress: progressByManga[manga.id ?? -1]?.fraction ?? 0
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { contextMenu(for: manga) }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for manga: Manga) -> some View {
        Button {
            mangaToRemove = manga
            isConfirmingRemoval = true
        } label: {
            Label("Remove from Library", systemImage: "trash")
        }

        if let id = manga.id {
            Button {
                Task {
                    try? await chapterRepo.markAllChaptersRead(forMangaId: id)
                    await loadLibrary(showsSpinner: false)
                }
            } label: {
                Label("Mark All Read", systemImage: "checkmark.circle")
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(YomiTheme.surface)
                    .aspectRatio(3.0 / 4.2, contentMode: .fit)
                    .overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.65))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if mangas.isEmpty {
            YomiEmptyState(
                icon: "books.vertical",
                title: "Your Library Is Empty",
                message: "Discover and add manga from Sources to begin reading.",
                actionTitle: "Browse Sources"
            ) {
                router.openSources()
            }
        } else if !searchQuery.isEmpty {
            YomiEmptyState(
                icon: "magnifyingglass",
                title: "No Results",
                message: "No library titles match \"\(searchQuery)\".",
                actionTitle: "Clear Search"
            ) {
                searchQuery = ""
            }
        } else {
            YomiEmptyState(
                icon: "tray",
                title: "No Titles in Category",
                message: "This category does not have any manga yet.",
                actionTitle: "Show All Titles"
            ) {
                selectedCategoryId = nil
                filterRaw = LibraryFilter.all.rawValue
            }
        }
    }

    // MARK: - Data Management

    private func loadLibrary(showsSpinner: Bool = true) async {
        if showsSpinner { isLoading = true }
        do {
            async let categoriesTask = categoryRepo.getAllCategories()
            async let categoryCountsTask = categoryRepo.getCategoryMangaCounts()
            async let totalCountTask = mangaRepo.getLibraryMangaCount()
            async let progressTask = chapterRepo.getLibraryProgress()
            async let historyTask = historyRepo.getHistory(limit: 250)

            let loadedCategories = try await categoriesTask
            let loadedCategoryCounts = (try? await categoryCountsTask) ?? [:]
            let loadedTotalCount = (try? await totalCountTask) ?? 0
            let loadedMangas: [Manga]
            if let selectedCategoryId {
                loadedMangas = try await mangaRepo.getLibraryMangas(forCategoryId: selectedCategoryId)
            } else {
                loadedMangas = try await mangaRepo.getLibraryMangas()
            }
            let progress = (try? await progressTask) ?? [:]
            let history = (try? await historyTask) ?? []
            let libraryIds = Set(loadedMangas.compactMap(\.id))

            var lastRead: [Int64: Date] = [:]
            for item in history where libraryIds.contains(item.mangaId) && lastRead[item.mangaId] == nil {
                lastRead[item.mangaId] = item.readAt
            }

            categories = loadedCategories
            categoryCounts = loadedCategoryCounts
            totalLibraryCount = loadedTotalCount
            mangas = loadedMangas
            progressByManga = progress
            lastReadByManga = lastRead
            downloadCounts = downloadManager.downloadedChapterCounts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func selectCategory(_ category: YomiCategory?) {
        guard let category, category.isLocked, !privacyManager.isCategoryUnlocked(category) else {
            selectedCategoryId = category?.id
            return
        }

        Task {
            let unlocked = await biometricManager.requestUnlock(reason: "Unlock \(category.name)")
            if unlocked {
                await MainActor.run {
                    privacyManager.unlockCategory(category)
                    selectedCategoryId = category.id
                }
            }
        }
    }

    private func removeFromLibrary() {
        guard let manga = mangaToRemove, let id = manga.id else { return }
        Task {
            try? await mangaRepo.setInLibrary(mangaId: id, inLibrary: false)
            await loadLibrary(showsSpinner: false)
        }
    }
}
