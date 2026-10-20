import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

/// Editorial manga detail view designed for instant reading and clear chapter management.
public struct MangaDetailView: View {
    @State public var manga: Manga
    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters: Bool = false
    @State private var isInLibrary: Bool = false
    @State private var activeChapterForReading: Chapter?
    @State private var isShowingTrackingSheet: Bool = false
    @State private var isShowingCategorySheet: Bool = false
    @State private var isSynopsisExpanded: Bool = false
    @State private var chapterFilter: MangaChapterFilter = .all
    @State private var chapterSort: MangaChapterSort = .newest
    @State private var chapterSearch: String = ""
    @State private var downloadedChapterIds: Set<Int64> = []
    @State private var errorMessage: String?
    @State private var isShowingMarkAllConfirmation: Bool = false
    @State private var isSourceAvailable: Bool = true

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let downloadManager = DownloadManager.shared
    private let extensionManager = ExtensionManager.shared

    public init(manga: Manga) {
        self._manga = State(initialValue: manga)
        self._isInLibrary = State(initialValue: manga.inLibrary)
    }

    private var visibleChapters: [Chapter] {
        var items = chapters

        switch chapterFilter {
        case .all:
            break
        case .unread:
            items = items.filter { !$0.read }
        case .bookmarked:
            items = items.filter(\.bookmark)
        case .downloaded:
            items = items.filter { chapter in
                guard let id = chapter.id else { return false }
                return downloadedChapterIds.contains(id)
            }
        }

        let query = chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || ($0.scanlator?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        return items.sorted { lhs, rhs in
            let lhsNumber = lhs.chapterNumber >= 0 ? lhs.chapterNumber : Float(lhs.sourceOrder)
            let rhsNumber = rhs.chapterNumber >= 0 ? rhs.chapterNumber : Float(rhs.sourceOrder)
            if lhsNumber == rhsNumber {
                return chapterSort == .newest ? lhs.sourceOrder > rhs.sourceOrder : lhs.sourceOrder < rhs.sourceOrder
            }
            return chapterSort == .newest ? lhsNumber > rhsNumber : lhsNumber < rhsNumber
        }
    }

    private var readCount: Int {
        chapters.filter(\.read).count
    }

    private var unreadCount: Int {
        max(0, chapters.count - readCount)
    }

    private var progressFraction: Double {
        guard !chapters.isEmpty else { return 0 }
        return Double(readCount) / Double(chapters.count)
    }

    private var resumeChapter: Chapter? {
        if let inProgress = chapters.first(where: { !$0.read && $0.lastPageRead > 0 }) {
            return inProgress
        }
        if let unread = chapters.first(where: { !$0.read }) {
            return unread
        }
        return chapters.first
    }

    private var sourceName: String {
        extensionManager.getSource(id: manga.sourceId)?.manifest.name ?? "Custom Source"
    }

    private var resumeTitle: String {
        guard let resumeChapter else { return "No Chapters" }
        if resumeChapter.lastPageRead > 0 && !resumeChapter.read {
            return "Resume Ch. \(chapterNumberText(resumeChapter))"
        }
        return readCount > 0 ? "Continue Reading" : "Start Reading"
    }

    public var body: some View {
        ZStack {
            YomiBackground(showsGlow: false)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    MangaDetailHeroView(
                        manga: manga,
                        sourceName: sourceName,
                        chapterCount: chapters.count
                    )

                    MangaDetailActionRow(
                        resumeTitle: resumeTitle,
                        canRead: !chapters.isEmpty,
                        isInLibrary: isInLibrary,
                        onResume: {
                            guard let resumeChapter else { return }
                            activeChapterForReading = resumeChapter
                        },
                        onToggleLibrary: { toggleLibrary() },
                        onDownloadUnread: { downloadAllUnread() },
                        onDownloadAll: { downloadAllChapters() }
                    )

                    if !isSourceAvailable {
                        MangaDetailSourceUnavailableBanner()
                    }

                    if let errorMessage {
                        MangaDetailErrorBanner(message: errorMessage)
                    }

                    if progressFraction > 0 {
                        MangaDetailProgressView(
                            readCount: readCount,
                            totalCount: chapters.count,
                            progressFraction: progressFraction
                        )
                    }

                    if let description = manga.description, !description.isEmpty {
                        MangaDetailSynopsisView(
                            description: description,
                            genres: manga.genres,
                            isExpanded: $isSynopsisExpanded
                        )
                    }

                    chaptersSection
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable { await loadChapters(forceRefresh: true) }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .task { await loadChapters() }
        .sheet(isPresented: $isShowingCategorySheet) {
            if let mangaId = manga.id {
                MangaCategorySheet(mangaId: mangaId) {
                    Task { await loadChapters(forceRefresh: false) }
                }
            }
        }
        .sheet(isPresented: $isShowingTrackingSheet) {
            MangaTrackingSheet(manga: manga) {
                Task { await loadChapters(forceRefresh: false) }
            }
        }
        .confirmationDialog(
            "Mark all \(chapters.count) chapters as read?",
            isPresented: $isShowingMarkAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark All Read", role: .destructive) { markAllRead() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes reading progress flags only. Downloaded archives remain intact.")
        }
        .yomiFullScreenCover(item: $activeChapterForReading, onDismiss: {
            Task { await loadChapters(forceRefresh: false) }
        }) { chapter in
            ReaderContainerView(manga: manga, chapter: chapter)
        }
    }

    // MARK: - Subviews

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Chapters (\(chapters.count))")
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                Spacer()

                if !chapters.isEmpty {
                    Button {
                        isShowingMarkAllConfirmation = true
                    } label: {
                        Text("Mark All")
                            .font(YomiFont.caption.weight(.semibold))
                            .foregroundStyle(YomiTheme.accentStrong)
                    }
                }
            }
            .padding(.top, 8)

            if !chapters.isEmpty {
                MangaChapterFilterBar(filter: $chapterFilter, sort: $chapterSort)
            }

            if isLoadingChapters && chapters.isEmpty {
                VStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle()
                            .fill(YomiTheme.surface)
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if chapters.isEmpty {
                YomiEmptyState(
                    icon: "books.vertical",
                    title: "No Chapters Available",
                    message: "Pull down to refresh or check your network connection.",
                    actionTitle: "Refresh"
                ) {
                    Task { await loadChapters(forceRefresh: true) }
                }
            } else if visibleChapters.isEmpty {
                YomiEmptyState(
                    icon: "magnifyingglass",
                    title: "No Matching Chapters",
                    message: "Try clearing the search or switching filters.",
                    actionTitle: "Clear Filters"
                ) {
                    chapterFilter = .all
                    chapterSearch = ""
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleChapters, id: \.stableId) { chapter in
                        DetailChapterRow(
                            chapter: chapter,
                            isDownloaded: chapter.id.map { downloadedChapterIds.contains($0) } ?? false,
                            onTap: { activeChapterForReading = chapter },
                            onToggleRead: { toggleChapterRead(chapter) },
                            onToggleBookmark: { toggleChapterBookmark(chapter) },
                            onDownload: { downloadChapter(chapter) }
                        )
                    }
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                isShowingCategorySheet = true
            } label: {
                Label("Categories", systemImage: "folder")
            }

            Button {
                isShowingTrackingSheet = true
            } label: {
                Label("Tracking", systemImage: "arrow.triangle.2.circlepath")
            }

            Menu {
                ForEach(MangaViewer.allCases, id: \.self) { viewer in
                    Button {
                        setViewer(viewer)
                    } label: {
                        if manga.viewer == viewer {
                            Label(viewer.title, systemImage: "checkmark")
                        } else {
                            Text(viewer.title)
                        }
                    }
                }
            } label: {
                Label("Reading Direction", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            if isInLibrary {
                Button(role: .destructive) {
                    toggleLibrary()
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(YomiTheme.textSecondary)
        }
    }

    // MARK: - Data Operations

    private func loadChapters(forceRefresh: Bool = true) async {
        if chapters.isEmpty { isLoadingChapters = true }

        var current = manga
        do {
            if let existing = try await mangaRepo.getManga(sourceId: current.sourceId, url: current.url) {
                current = existing
                manga = existing
                isInLibrary = existing.inLibrary
            } else if current.id == nil {
                let saved = try await mangaRepo.upsert(current)
                current = saved
                manga = saved
                isInLibrary = saved.inLibrary
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        guard let mangaId = current.id else {
            isLoadingChapters = false
            return
        }

        if let local = try? await chapterRepo.getChapters(forMangaId: mangaId) {
            chapters = local
        }
        downloadedChapterIds = downloadManager.downloadedChapterIDs()
        if !chapters.isEmpty { isLoadingChapters = false }

        guard forceRefresh, let source = extensionManager.getSource(id: current.sourceId) else {
            isSourceAvailable = extensionManager.getSource(id: current.sourceId) != nil
            isLoadingChapters = false
            return
        }

        isSourceAvailable = true
        errorMessage = nil

        do {
            if let freshDetails = try? await source.getMangaDetails(manga: current) {
                var merged = freshDetails
                merged.id = current.id
                merged.inLibrary = current.inLibrary
                merged.viewer = current.viewer
                merged.customThumbnailUrl = current.customThumbnailUrl
                if let saved = try? await mangaRepo.upsert(merged) {
                    manga = saved
                    current = saved
                }
            }

            if let freshChapters = try? await source.getChapterList(manga: current) {
                let synced = try await chapterRepo.syncChapters(freshChapters, forMangaId: mangaId)
                chapters = synced
            } else if chapters.isEmpty {
                errorMessage = "Source returned no chapters."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        downloadedChapterIds = downloadManager.downloadedChapterIDs()
        isLoadingChapters = false
    }

    private func toggleLibrary() {
        let newValue = !isInLibrary
        isInLibrary = newValue
        manga.inLibrary = newValue

        Task {
            if manga.id == nil {
                if let saved = try? await mangaRepo.upsert(manga) {
                    manga = saved
                }
            }
            guard let mangaId = manga.id else { return }
            try? await mangaRepo.setInLibrary(mangaId: mangaId, inLibrary: newValue)
        }
    }

    private func toggleChapterRead(_ chapter: Chapter) {
        guard let chapterId = chapter.id else { return }
        let newStatus = !chapter.read

        if let index = chapters.firstIndex(where: { $0.id == chapterId }) {
            chapters[index].read = newStatus
        }

        Task {
            try? await chapterRepo.updateProgress(
                chapterId: chapterId,
                lastPageRead: chapter.lastPageRead,
                isRead: newStatus,
                logHistory: false
            )
        }
    }

    private func toggleChapterBookmark(_ chapter: Chapter) {
        guard let chapterId = chapter.id else { return }
        let newBookmark = !chapter.bookmark

        if let index = chapters.firstIndex(where: { $0.id == chapterId }) {
            chapters[index].bookmark = newBookmark
        }

        Task {
            try? await chapterRepo.setBookmark(chapterId: chapterId, isBookmarked: newBookmark)
        }
    }

    private func markAllRead() {
        guard let mangaId = manga.id else { return }
        Task {
            try? await chapterRepo.markAllChaptersRead(forMangaId: mangaId)
            await loadChapters(forceRefresh: false)
        }
    }

    private func setViewer(_ viewer: MangaViewer) {
        manga.viewer = viewer
        guard let mangaId = manga.id else { return }
        Task {
            try? await mangaRepo.updateViewer(mangaId: mangaId, viewer: viewer)
        }
    }

    private func downloadChapter(_ chapter: Chapter) {
        guard let source = extensionManager.getSource(id: manga.sourceId) else { return }
        downloadManager.enqueue(manga: manga, chapters: [chapter], source: source)
    }

    private func downloadAllUnread() {
        guard let source = extensionManager.getSource(id: manga.sourceId) else { return }
        let unread = chapters.filter { !$0.read && !($0.id.map { downloadedChapterIds.contains($0) } ?? false) }
        guard !unread.isEmpty else { return }
        downloadManager.enqueue(manga: manga, chapters: unread, source: source)
    }

    private func downloadAllChapters() {
        guard let source = extensionManager.getSource(id: manga.sourceId) else { return }
        downloadManager.enqueue(manga: manga, chapters: chapters, source: source)
    }

    private func chapterNumberText(_ chapter: Chapter) -> String {
        guard chapter.chapterNumber >= 0 else { return "?" }
        return chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", chapter.chapterNumber)
            : String(format: "%.1f", chapter.chapterNumber)
    }
}
