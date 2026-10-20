import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

/// Chronological release feed for titles in the user's library.
public struct UpdatesView: View {
    @State private var updates: [ChapterUpdateItem] = []
    @State private var isLoading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var refreshCompleted: Int = 0
    @State private var refreshTotal: Int = 0
    @State private var refreshFailures: Int = 0
    @State private var lastRefresh: Date?
    @State private var filter: UpdateFilter = .all
    @State private var downloadedIDs: Set<Int64> = []
    @State private var readerRequest: ReaderRequest?
    @State private var detailManga: Manga?
    @State private var downloadToRemove: ChapterUpdateItem?

    private let chapterRepo = ChapterRepository()
    private let mangaRepo = MangaRepository()
    private let extensionManager = ExtensionManager.shared
    private let downloadManager = DownloadManager.shared
    private let privacyManager = PrivacyManager.shared

    public init() {}

    private var unreadCount: Int {
        updates.filter { !$0.read }.count
    }

    private var filteredUpdates: [ChapterUpdateItem] {
        switch filter {
        case .all:
            return updates
        case .unread:
            return updates.filter { !$0.read }
        case .downloaded:
            return updates.filter { downloadedIDs.contains($0.chapterId) }
        case .bookmarked:
            return updates.filter(\.bookmark)
        }
    }

    private var sections: [UpdateDateSection] {
        let calendar = Calendar.current
        var today: [ChapterUpdateItem] = []
        var yesterday: [ChapterUpdateItem] = []
        var week: [ChapterUpdateItem] = []
        var older: [ChapterUpdateItem] = []

        for item in filteredUpdates {
            let date = item.dateUpload > Date(timeIntervalSince1970: 86_400) ? item.dateUpload : item.dateFetch
            if calendar.isDateInToday(date) {
                today.append(item)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(item)
            } else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days <= 7 {
                week.append(item)
            } else {
                older.append(item)
            }
        }

        var result: [UpdateDateSection] = []
        if !today.isEmpty { result.append(UpdateDateSection(title: "Today", items: today)) }
        if !yesterday.isEmpty { result.append(UpdateDateSection(title: "Yesterday", items: yesterday)) }
        if !week.isEmpty { result.append(UpdateDateSection(title: "Past 7 Days", items: week)) }
        if !older.isEmpty { result.append(UpdateDateSection(title: "Older", items: older)) }
        return result
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                VStack(spacing: 0) {
                    if isRefreshing && refreshTotal > 0 {
                        refreshProgressBar
                    }

                    filterBar

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if privacyManager.isIncognitoMode {
                                incognitoNotice
                            }

                            if isLoading && updates.isEmpty {
                                ProgressView()
                                    .tint(YomiTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else if filteredUpdates.isEmpty {
                                emptyState
                            } else {
                                ForEach(sections, id: \.title) { section in
                                    updateSection(section)
                                }
                            }
                        }
                        .padding(.horizontal, YomiTheme.contentPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await refreshUpdatesFromSources() }
                }
            }
            .navigationTitle("Updates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if unreadCount > 0 {
                        Text("\(unreadCount) unread")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if unreadCount > 0 {
                        Button {
                            markAllRead()
                        } label: {
                            Text("Mark All")
                                .font(YomiFont.caption.weight(.semibold))
                                .foregroundStyle(YomiTheme.accentStrong)
                        }
                    }

                    Button {
                        Task { await refreshUpdatesFromSources() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .tint(YomiTheme.textSecondary)
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .navigationDestination(item: $detailManga) { manga in
                MangaDetailView(manga: manga)
            }
            .yomiFullScreenCover(item: $readerRequest, onDismiss: {
                Task { await loadUpdates() }
            }) { request in
                ReaderContainerView(manga: request.manga, chapter: request.chapter)
            }
            .confirmationDialog(
                "Remove downloaded chapter?",
                isPresented: Binding(
                    get: { downloadToRemove != nil },
                    set: { if !$0 { downloadToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let item = downloadToRemove {
                    Button("Delete Download", role: .destructive) {
                        removeDownload(item)
                    }
                }
                Button("Keep", role: .cancel) { downloadToRemove = nil }
            } message: {
                Text("The chapter stays available from its source.")
            }
            .task { await loadUpdates() }
        }
    }

    // MARK: - Subviews

    private var refreshProgressBar: some View {
        YomiProgressBar(
            value: Double(refreshCompleted) / Double(max(refreshTotal, 1)),
            tint: YomiTheme.accentStrong,
            height: 2
        )
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(UpdateFilter.allCases, id: \.self) { option in
                    YomiFilterChip(
                        title: option.title,
                        isSelected: filter == option,
                        icon: nil
                    ) {
                        filter = option
                    }
                }
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.vertical, 8)
        }
        .background(YomiTheme.pureBlack)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
    }

    private var incognitoNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .medium))
            Text("Incognito · Reading history is not saved")
                .font(YomiFont.caption)
        }
        .foregroundStyle(YomiTheme.accentStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YomiTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func updateSection(_ section: UpdateDateSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.title)
                    .font(YomiFont.micro)
                    .tracking(1.2)
                    .foregroundStyle(YomiTheme.textTertiary)
                Spacer()
                Text("\(section.items.count)")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
            }
            .padding(.top, 4)

            LazyVStack(spacing: 0) {
                ForEach(section.items) { item in
                    updateRow(item)
                }
            }
        }
    }

    private func updateRow(_ item: ChapterUpdateItem) -> some View {
        HStack(spacing: 12) {
            Button {
                openDetail(for: item)
            } label: {
                YomiCoverImage(
                    urlString: item.effectiveThumbnailUrl,
                    title: item.mangaTitle,
                    cornerRadius: 6
                )
                .frame(width: 44, height: 62)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.mangaTitle)
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.read {
                        Circle()
                            .fill(YomiTheme.unreadBadge)
                            .frame(width: 5, height: 5)
                    }
                    Text(item.displayChapterTitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(item.read ? YomiTheme.textTertiary : YomiTheme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    YomiTag(sourceName(for: item.sourceId), tint: YomiTheme.textTertiary)
                    Text(relativeDate(item))
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                    if downloadedIDs.contains(item.chapterId) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(YomiTheme.success)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button {
                    openReader(for: item)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(YomiTheme.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    toggleDownload(item)
                } label: {
                    Image(systemName: downloadedIDs.contains(item.chapterId) ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(downloadedIDs.contains(item.chapterId) ? YomiTheme.success : YomiTheme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
        .contextMenu {
            Button {
                toggleRead(item)
            } label: {
                Label(item.read ? "Mark as Unread" : "Mark as Read", systemImage: item.read ? "envelope.badge" : "checkmark.circle")
            }
            Button {
                toggleDownload(item)
            } label: {
                Label(downloadedIDs.contains(item.chapterId) ? "Delete Download" : "Download Chapter", systemImage: downloadedIDs.contains(item.chapterId) ? "trash" : "arrow.down.circle")
            }
            Button {
                openDetail(for: item)
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }

    private var emptyState: some View {
        YomiEmptyState(
            icon: "bolt.slash",
            title: filter == .all ? "No Recent Updates" : "Nothing Here",
            message: filter == .all
                ? "New chapters from library manga will appear here. Pull down to check your sources."
                : "No updates match this filter.",
            actionTitle: filter == .all ? "Check for Updates" : "Show All",
            action: {
                if filter == .all {
                    Task { await refreshUpdatesFromSources() }
                } else {
                    filter = .all
                }
            }
        )
    }

    // MARK: - Actions

    private func loadUpdates() async {
        isLoading = true
        updates = (try? await chapterRepo.getRecentUpdates(limit: 250)) ?? []
        downloadedIDs = downloadManager.downloadedChapterIDs()
        isLoading = false
    }

    private func refreshUpdatesFromSources() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshCompleted = 0
        refreshFailures = 0

        let libraryMangas = (try? await mangaRepo.getLibraryMangas()) ?? []
        refreshTotal = libraryMangas.count

        let batchSize = 4
        var index = 0
        while index < libraryMangas.count {
            let batch = Array(libraryMangas[index..<min(index + batchSize, libraryMangas.count)])
            await withTaskGroup(of: Bool.self) { group in
                for manga in batch {
                    group.addTask {
                        guard let mangaId = manga.id,
                              let source = extensionManager.getSource(id: manga.sourceId) else {
                            return false
                        }
                        do {
                            let chapters = try await source.getChapterList(manga: manga)
                            _ = try await self.chapterRepo.syncChapters(chapters, forMangaId: mangaId)
                            return true
                        } catch {
                            return false
                        }
                    }
                }

                for await success in group {
                    await MainActor.run {
                        refreshCompleted += 1
                        if !success { refreshFailures += 1 }
                    }
                }
            }
            index += batchSize
        }

        await loadUpdates()
        lastRefresh = Date()
        isRefreshing = false
    }

    private func markAllRead() {
        Task {
            try? await chapterRepo.markAllLibraryChaptersRead()
            for index in updates.indices {
                updates[index].read = true
            }
        }
    }

    private func toggleRead(_ item: ChapterUpdateItem) {
        let newStatus = !item.read
        Task {
            try? await chapterRepo.updateProgress(
                chapterId: item.chapterId,
                lastPageRead: item.lastPageRead,
                isRead: newStatus,
                logHistory: false
            )
            await MainActor.run {
                if let index = updates.firstIndex(where: { $0.chapterId == item.chapterId }) {
                    updates[index].read = newStatus
                }
            }
        }
    }

    private func toggleDownload(_ item: ChapterUpdateItem) {
        if downloadedIDs.contains(item.chapterId) {
            downloadToRemove = item
            return
        }
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId),
                  let chapter = try? await chapterRepo.getChapter(id: item.chapterId),
                  let source = extensionManager.getSource(id: item.sourceId) else { return }
            downloadManager.enqueue(manga: manga, chapters: [chapter], source: source)
        }
    }

    private func removeDownload(_ item: ChapterUpdateItem) {
        do {
            try downloadManager.deleteDownloadedChapter(
                chapterId: item.chapterId,
                mangaId: item.mangaId
            )
            downloadedIDs.remove(item.chapterId)
        } catch {
            print("[Updates] Failed to delete download: \(error)")
        }
        downloadToRemove = nil
    }

    private func openReader(for item: ChapterUpdateItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId),
                  let chapter = try? await chapterRepo.getChapter(id: item.chapterId) else { return }
            await MainActor.run {
                readerRequest = ReaderRequest(manga: manga, chapter: chapter)
            }
        }
    }

    private func openDetail(for item: ChapterUpdateItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId) else { return }
            await MainActor.run {
                detailManga = manga
            }
        }
    }

    private func sourceName(for sourceId: Int64) -> String {
        extensionManager.getSource(id: sourceId)?.manifest.name ?? "Source"
    }

    private func relativeDate(_ item: ChapterUpdateItem) -> String {
        let date = item.dateUpload > Date(timeIntervalSince1970: 86_400) ? item.dateUpload : item.dateFetch
        guard date > Date(timeIntervalSince1970: 86_400) else { return "Recently" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Models

private struct UpdateDateSection {
    let title: String
    let items: [ChapterUpdateItem]
}

public enum UpdateFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case downloaded = "Offline"
    case bookmarked = "Bookmarked"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "bolt.fill"
        case .unread: return "circle.fill"
        case .downloaded: return "arrow.down.circle.fill"
        case .bookmarked: return "bookmark.fill"
        }
    }
}
