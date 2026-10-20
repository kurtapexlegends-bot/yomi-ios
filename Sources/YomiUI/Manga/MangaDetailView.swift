import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

/// Manga detail rebuilt around a clear reading path: progress, resume, chapter filters,
/// bookmarking, downloads, categories, and tracker links.
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

    private var bookmarkCount: Int {
        chapters.filter(\.bookmark).count
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
        extensionManager.getSource(id: manga.sourceId)?.manifest.name ?? "Removed source"
    }

    private var resumeTitle: String {
        guard let resumeChapter else { return "No Chapters" }
        if resumeChapter.lastPageRead > 0 && !resumeChapter.read {
            return "Continue Ch. \(chapterNumberText(resumeChapter))"
        }
        return readCount > 0 ? "Continue Reading" : "Start Reading"
    }

    public var body: some View {
        ZStack {
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    heroCard
                    actionRow

                    if !isSourceAvailable {
                        sourceUnavailableBanner
                    }

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    progressCard

                    if let description = manga.description, !description.isEmpty {
                        synopsisCard(description)
                    }

                    chaptersSection
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 10)
                .padding(.bottom, 34)
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
            Text("This changes reading flags only. Bookmarks and downloads stay intact.")
        }
        .yomiFullScreenCover(item: $activeChapterForReading, onDismiss: {
            Task { await loadChapters(forceRefresh: false) }
        }) { chapter in
            ReaderContainerView(manga: manga, chapter: chapter)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        YomiCard(padding: 16) {
            HStack(alignment: .top, spacing: 15) {
                YomiCoverImage(
                    urlString: manga.effectiveThumbnailUrl,
                    title: manga.title,
                    cornerRadius: 12
                )
                .frame(width: 116, height: 166)
                .clipped()
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 7) {
                    Text(manga.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(4)

                    if let author = manga.author, !author.isEmpty {
                        Text(author)
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        YomiTag(manga.status.title, tint: statusTint)
                        if !chapters.isEmpty {
                            YomiTag("\(chapters.count) chapters", tint: YomiTheme.accentStrong)
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .semibold))
                        Text(sourceName)
                            .font(YomiFont.micro)
                            .lineLimit(1)
                    }
                    .foregroundStyle(YomiTheme.textTertiary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var statusTint: Color {
        switch manga.status {
        case .ongoing: return YomiTheme.success
        case .completed, .publishingFinished: return YomiTheme.unreadBadge
        case .cancelled, .licensed: return YomiTheme.danger
        case .onHiatus: return YomiTheme.warning
        case .unknown: return YomiTheme.textSecondary
        }
    }

    private var actionRow: some View {
        HStack(spacing: 9) {
            Button {
                guard let resumeChapter else { return }
                activeChapterForReading = resumeChapter
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: resumeChapter?.read == true ? "arrow.counterclockwise" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(resumeTitle)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(YomiPrimaryButtonStyle())
            .disabled(chapters.isEmpty)

            Button {
                toggleLibrary()
            } label: {
                Image(systemName: isInLibrary ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isInLibrary ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(isInLibrary ? YomiTheme.accentSoft : YomiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(isInLibrary ? YomiTheme.accent.opacity(0.4) : YomiTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isInLibrary ? "Remove from library" : "Add to library")

            Menu {
                Button {
                    downloadAllUnread()
                } label: {
                    Label("Download \(unreadCount) Unread", systemImage: "arrow.down.circle")
                }
                Button {
                    downloadAllChapters()
                } label: {
                    Label("Download All", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(YomiTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(YomiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(YomiTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chapters.isEmpty)
        }
    }

    private var sourceUnavailableBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(YomiTheme.warning)
            Text("This source is not installed. Downloaded chapters remain readable, but new chapters cannot be fetched.")
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(YomiTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(YomiTheme.warning)
            Text(message)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(YomiTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Progress

    private var progressCard: some View {
        YomiCard(padding: 15) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Reading progress")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Text("\(Int(progressFraction * 100))%")
                        .font(YomiFont.number)
                        .foregroundStyle(YomiTheme.accentStrong)
                }

                YomiProgressBar(value: progressFraction, tint: YomiTheme.accentStrong, height: 5)

                HStack(spacing: 0) {
                    progressStat(value: "\(readCount)", label: "Read")
                    progressDivider
                    progressStat(value: "\(unreadCount)", label: "Unread")
                    progressDivider
                    progressStat(value: "\(bookmarkCount)", label: "Bookmarked")
                    progressDivider
                    progressStat(value: "\(downloadedChapterIds.count)", label: "Offline")
                }
            }
        }
    }

    private func progressStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(YomiTheme.textPrimary)
            Text(label)
                .font(YomiFont.micro)
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressDivider: some View {
        Rectangle()
            .fill(YomiTheme.border)
            .frame(width: 1, height: 26)
            .padding(.horizontal, 8)
    }

    // MARK: - Synopsis

    private func synopsisCard(_ description: String) -> some View {
        YomiCard(padding: 15) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("About")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    if manga.lastUpdate > Date(timeIntervalSince1970: 86_400) {
                        Text(relativeUpdate)
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                    }
                }

                Text(description)
                    .font(YomiFont.body)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(isSynopsisExpanded ? nil : 5)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isSynopsisExpanded.toggle()
                    }
                } label: {
                    Text(isSynopsisExpanded ? "Show less" : "Read more")
                        .font(YomiFont.caption.weight(.bold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
                .buttonStyle(.plain)

                if !manga.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(manga.genres, id: \.self) { genre in
                                YomiTag(genre, tint: YomiTheme.accentStrong)
                            }
                        }
                    }
                }
            }
        }
    }

    private var relativeUpdate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: manga.lastUpdate, relativeTo: Date()))"
    }

    // MARK: - Chapters

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader(
                "Chapters",
                subtitle: "\(visibleChapters.count) of \(chapters.count)",
                actionTitle: chapters.isEmpty ? nil : "Mark All Read",
                action: chapters.isEmpty ? nil : { isShowingMarkAllConfirmation = true }
            )

            if !chapters.isEmpty {
                chapterControls
            }

            if isLoadingChapters && chapters.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(YomiTheme.surface)
                            .frame(height: 58)
                    }
                }
            } else if chapters.isEmpty {
                YomiEmptyState(
                    icon: "text.book.closed",
                    title: "No Chapters",
                    message: isSourceAvailable
                        ? "This source has not returned chapters yet. Pull to refresh."
                        : "This source was removed, so no new chapters can be fetched.",
                    actionTitle: isSourceAvailable ? "Refresh" : nil,
                    action: isSourceAvailable ? { Task { await loadChapters(forceRefresh: true) } } : nil
                )
            } else if visibleChapters.isEmpty {
                YomiEmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "Nothing Matches",
                    message: "No chapters match this filter or search.",
                    actionTitle: "Clear Filters",
                    action: {
                        chapterFilter = .all
                        chapterSearch = ""
                    }
                )
            } else {
                LazyVStack(spacing: 7) {
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

    private var chapterControls: some View {
        VStack(spacing: 8) {
            YomiSearchField(text: $chapterSearch, placeholder: "Find a chapter")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(MangaChapterFilter.allCases, id: \.self) { option in
                        YomiFilterChip(
                            title: option.title,
                            isSelected: chapterFilter == option,
                            icon: option.icon
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) { chapterFilter = option }
                        }
                    }

                    Menu {
                        ForEach(MangaChapterSort.allCases, id: \.self) { option in
                            Button {
                                chapterSort = option
                            } label: {
                                if chapterSort == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text(chapterSort == .newest ? "Newest" : "Oldest")
                                .font(YomiFont.caption.weight(.semibold))
                        }
                        .foregroundStyle(YomiTheme.textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(YomiTheme.surface)
                        .overlay(Capsule().stroke(YomiTheme.border, lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - More menu

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
                Label("Reading Mode", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            Button {
                downloadAllUnread()
            } label: {
                Label("Download Unread", systemImage: "arrow.down.circle")
            }

            Button {
                isShowingMarkAllConfirmation = true
            } label: {
                Label("Mark All Read", systemImage: "checkmark.circle")
            }

            if isInLibrary {
                Button(role: .destructive) {
                    toggleLibrary()
                } label: {
                    Label("Remove from Library", systemImage: "heart.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YomiTheme.textSecondary)
        }
    }

    // MARK: - Data

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
                chapters = synced.sorted { lhs, rhs in
                    if lhs.chapterNumber == rhs.chapterNumber {
                        return lhs.sourceOrder < rhs.sourceOrder
                    }
                    return lhs.chapterNumber > rhs.chapterNumber
                }
            } else if chapters.isEmpty {
                errorMessage = "The source did not return a chapter list. It may be unavailable or blocked."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        downloadedChapterIds = downloadManager.downloadedChapterIDs()
        isLoadingChapters = false
    }

    // MARK: - Actions

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
