import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload

public struct LibraryView: View {
    @State private var mangas: [Manga] = []
    @State private var categories: [YomiCategory] = []
    @State private var selectedCategoryId: Int64? = nil
    @State private var searchQuery: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var progressByManga: [Int64: MangaChapterProgress] = [:]
    @State private var lastReadByManga: [Int64: Date] = [:]
    @State private var downloadCounts: [Int64: Int] = [:]
    @State private var recentHistory: [HistoryItem] = []

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
        GridItem(.adaptive(minimum: 108, maximum: 158), spacing: 12)
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

    private var downloadedTotal: Int {
        downloadCounts.values.reduce(0, +)
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
                YomiBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header

                        if privacyManager.isIncognitoMode {
                            incognitoBanner
                        }

                        if !recentHistory.isEmpty && searchQuery.isEmpty && filter == .all {
                            continueReadingSection
                        }

                        statsStrip
                        categoryShelf
                        filterShelf

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
                        }
                    }
                    .padding(.horizontal, YomiTheme.contentPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .refreshable { await loadLibrary() }
            }
            .toolbar(.hidden, for: .navigationBar)
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
            .fullScreenCover(item: $readerRequest, onDismiss: {
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

    // MARK: - Header

    private var header: some View {
        YomiScreenHeader(
            title: "Library",
            subtitle: greetingSubtitle
        ) {
            HStack(spacing: 8) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .buttonStyle(YomiIconButtonStyle(tint: YomiTheme.textPrimary))

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        layoutRaw = isListLayout ? "grid" : "list"
                    }
                } label: {
                    Image(systemName: isListLayout ? "square.grid.2x2" : "list.bullet")
                }
                .buttonStyle(YomiIconButtonStyle(tint: YomiTheme.textPrimary))
            }
        }
    }

    private var greetingSubtitle: String {
        if let selectedCategory {
            return "\(displayedMangas.count) titles in \(selectedCategory.name)"
        }
        if unreadTotal > 0 {
            return "\(mangas.count) titles · \(unreadTotal) unread chapters"
        }
        return "\(mangas.count) titles · all caught up"
    }

    private var incognitoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Incognito mode · history and tracker writes are paused")
                .font(YomiFont.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 4)
        }
        .foregroundStyle(YomiTheme.accentStrong)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(YomiTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Continue reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader(
                "Continue Reading",
                subtitle: "Pick up exactly where you left off"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentHistory.prefix(8)) { item in
                        continueCard(item)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func continueCard(_ item: HistoryItem) -> some View {
        Button {
            openReader(for: item)
        } label: {
            HStack(spacing: 12) {
                YomiCoverImage(
                    urlString: item.effectiveThumbnailUrl,
                    title: item.mangaTitle,
                    cornerRadius: 12
                )
                .frame(width: 66, height: 94)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    Text(item.mangaTitle)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.displayChapterTitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9))
                        Text(item.lastPageRead > 0 ? "Page \(item.lastPageRead + 1)" : "Start chapter")
                            .font(YomiFont.micro)
                    }
                    .foregroundStyle(YomiTheme.accentStrong)
                    Spacer(minLength: 0)
                }
                .frame(width: 130, alignment: .leading)
            }
            .padding(10)
            .frame(width: 252, height: 114)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats

    private var statsStrip: some View {
        HStack(spacing: 10) {
            miniStat(value: "\(mangas.count)", label: "Titles", icon: "books.vertical.fill", tint: YomiTheme.accentStrong)
            miniStat(value: "\(unreadTotal)", label: "Unread", icon: "circle.fill", tint: YomiTheme.unreadBadge)
            miniStat(value: "\(downloadedTotal)", label: "Offline", icon: "arrow.down.circle.fill", tint: YomiTheme.success)
        }
    }

    private func miniStat(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(YomiFont.number)
                    .foregroundStyle(YomiTheme.textPrimary)
                Text(label)
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Category shelf

    private var categoryShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                YomiFilterChip(
                    title: "All",
                    isSelected: selectedCategoryId == nil,
                    icon: "square.grid.2x2.fill"
                ) {
                    selectCategory(nil)
                }

                ForEach(categories) { category in
                    YomiFilterChip(
                        title: category.name,
                        isSelected: selectedCategoryId == category.id,
                        icon: category.isLocked ? "lock.fill" : "folder.fill"
                    ) {
                        selectCategory(category)
                    }
                }

                Button {
                    isShowingCategoryManager = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YomiTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(YomiTheme.surface)
                        .overlay(Circle().stroke(YomiTheme.border, lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filterShelf: some View {
        HStack(spacing: 8) {
            YomiSearchField(text: $searchQuery, placeholder: "Filter library")
                .frame(maxWidth: .infinity)

            Menu {
                ForEach(LibraryFilter.allCases, id: \.self) { option in
                    Button {
                        filterRaw = option.rawValue
                    } label: {
                        Label(option.title, systemImage: option.icon)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(filter == .all ? YomiTheme.textSecondary : YomiTheme.accentStrong)
                    .frame(width: 44, height: 44)
                    .background(YomiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(filter == .all ? YomiTheme.border : YomiTheme.accent.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
            ForEach(displayedMangas) { manga in
                NavigationLink {
                    MangaDetailView(manga: manga)
                } label: {
                    MangaGridCard(
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

    private var listContent: some View {
        LazyVStack(spacing: 10) {
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
                Label("Mark All Chapters Read", systemImage: "checkmark.circle")
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .fill(YomiTheme.surface)
                    .aspectRatio(11.0 / 16.0, contentMode: .fit)
                    .overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.7))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if mangas.isEmpty {
            YomiEmptyState(
                icon: "books.vertical",
                title: "Your Library Is Waiting",
                message: "Add titles from Browse to build a personal, offline-friendly collection.",
                actionTitle: "Discover Sources"
            ) {
                router.openBrowse()
            }
        } else if !searchQuery.isEmpty {
            YomiEmptyState(
                icon: "magnifyingglass",
                title: "No Matches",
                message: "Try a shorter title, author name, or clear the active filter.",
                actionTitle: "Clear Search"
            ) {
                searchQuery = ""
                filterRaw = LibraryFilter.all.rawValue
            }
        } else {
            YomiEmptyState(
                icon: "line.3.horizontal.decrease.circle",
                title: "Nothing in This View",
                message: "No titles match this shelf and filter combination.",
                actionTitle: "Show Everything"
            ) {
                selectedCategoryId = nil
                filterRaw = LibraryFilter.all.rawValue
            }
        }
    }

    // MARK: - Data

    private func loadLibrary(showsSpinner: Bool = true) async {
        if showsSpinner { isLoading = true }
        do {
            async let categoriesTask = categoryRepo.getAllCategories()
            async let progressTask = chapterRepo.getLibraryProgress()
            async let historyTask = historyRepo.getHistory(limit: 250)

            let loadedCategories = try await categoriesTask
            let loadedMangas: [Manga]
            if let selectedCategoryId {
                loadedMangas = try await mangaRepo.getLibraryMangas(forCategoryId: selectedCategoryId)
            } else {
                loadedMangas = try await mangaRepo.getLibraryMangas()
            }
            let progress = (try? await progressTask) ?? [:]
            let history = (try? await historyTask) ?? []

            var lastRead: [Int64: Date] = [:]
            for item in history where lastRead[item.mangaId] == nil {
                lastRead[item.mangaId] = item.readAt
            }

            var seenMangaIds: Set<Int64> = []
            var recent: [HistoryItem] = []
            for item in history where !seenMangaIds.contains(item.mangaId) {
                seenMangaIds.insert(item.mangaId)
                recent.append(item)
                if recent.count == 8 { break }
            }

            categories = loadedCategories
            mangas = loadedMangas
            progressByManga = progress
            lastReadByManga = lastRead
            recentHistory = recent
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

    private func openReader(for item: HistoryItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId),
                  let chapter = try? await chapterRepo.getChapter(id: item.chapterId) else {
                return
            }
            await MainActor.run {
                readerRequest = ReaderRequest(manga: manga, chapter: chapter)
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

struct ReaderRequest: Identifiable {
    let id = UUID()
    let manga: Manga
    let chapter: Chapter
}

enum LibrarySort: String, CaseIterable {
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case lastUpdated = "Last Updated"
    case lastRead = "Last Read"
    case mostUnread = "Most Unread"
}

enum LibraryFilter: String, CaseIterable {
    case all = "All Titles"
    case unread = "Unread"
    case downloaded = "Downloaded"
    case completed = "Completed"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .unread: return "circle.fill"
        case .downloaded: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        }
    }
}

private struct LibraryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sort: LibrarySort
    let filter: LibraryFilter
    let onSelectSort: (LibrarySort) -> Void
    let onSelectFilter: (LibraryFilter) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section("Sort by") {
                            ForEach(LibrarySort.allCases, id: \.self) { option in
                                selectionRow(
                                    title: option.rawValue,
                                    icon: "arrow.up.arrow.down",
                                    selected: sort == option
                                ) {
                                    onSelectSort(option)
                                }
                            }
                        }

                        section("Filter") {
                            ForEach(LibraryFilter.allCases, id: \.self) { option in
                                selectionRow(
                                    title: option.title,
                                    icon: option.icon,
                                    selected: filter == option
                                ) {
                                    onSelectFilter(option)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Library View")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(YomiFont.micro)
                .tracking(1.4)
                .foregroundStyle(YomiTheme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(YomiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    private func selectionRow(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    .frame(width: 26)
                Text(title)
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
