import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

/// Displays chronologically grouped recent chapter releases for manga in the user's library.
public struct UpdatesView: View {
    @State private var updates: [ChapterUpdateItem] = []
    @State private var isLoading: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var activeChapterForReading: Chapter?
    @State private var activeMangaForReading: Manga?
    @State private var selectedMangaForDetail: Manga?

    private let chapterRepo = ChapterRepository()
    private let mangaRepo = MangaRepository()
    private let extensionManager = ExtensionManager.shared
    private let downloadManager = DownloadManager.shared
    private let privacyManager = PrivacyManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Incognito Mode Banner
                if privacyManager.isIncognitoMode {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                        Text("Incognito Mode Active")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.85))
                    .foregroundStyle(.white)
                }

                if isLoading && updates.isEmpty {
                    Spacer()
                    ProgressView("Checking for updates...")
                        .foregroundStyle(YomiTheme.textSecondary)
                    Spacer()
                } else if updates.isEmpty {
                    EmptyUpdatesView(onRefresh: {
                        Task { await refreshUpdatesFromSources() }
                    })
                } else {
                    List {
                        let sections = groupUpdatesByDate(updates)
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.items) { item in
                                    UpdateRowView(
                                        item: item,
                                        isDownloaded: isDownloaded(item),
                                        onRead: {
                                            openReader(for: item)
                                        },
                                        onDownload: {
                                            downloadChapter(item)
                                        },
                                        onToggleRead: {
                                            toggleReadStatus(item)
                                        },
                                        onViewManga: {
                                            openMangaDetail(for: item)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                    .refreshable {
                        await refreshUpdatesFromSources()
                    }
                }
            }
            .navigationTitle("Updates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(YomiTheme.accent)
                    }
                }
            }
            .onAppear {
                loadUpdates()
            }
            .navigationDestination(item: $selectedMangaForDetail) { manga in
                MangaDetailView(manga: manga)
            }
            #if os(iOS)
            .fullScreenCover(item: $activeChapterForReading) { chapter in
                if let manga = activeMangaForReading {
                    ReaderContainerView(manga: manga, chapter: chapter)
                }
            }
            #else
            .sheet(item: $activeChapterForReading) { chapter in
                if let manga = activeMangaForReading {
                    ReaderContainerView(manga: manga, chapter: chapter)
                }
            }
            #endif
            .onChange(of: activeChapterForReading) { oldVal, newVal in
                if oldVal != nil && newVal == nil {
                    loadUpdates()
                }
            }
        }
    }

    private func loadUpdates() {
        isLoading = true
        Task {
            updates = (try? await chapterRepo.getRecentUpdates(limit: 100)) ?? []
            isLoading = false
        }
    }

    private func refreshUpdatesFromSources() async {
        isRefreshing = true
        do {
            let libraryMangas = try await mangaRepo.getLibraryMangas()
            for manga in libraryMangas {
                guard let mangaId = manga.id,
                      let src = extensionManager.getSource(id: manga.sourceId) else { continue }
                if let freshChapters = try? await src.getChapterList(manga: manga) {
                    _ = try? await chapterRepo.syncChapters(freshChapters, forMangaId: mangaId)
                }
            }
            updates = (try? await chapterRepo.getRecentUpdates(limit: 100)) ?? []
        } catch {
            print("[UpdatesView] Error refreshing updates: \(error)")
        }
        isRefreshing = false
    }

    private func openReader(for item: ChapterUpdateItem) {
        Task { @MainActor in
            if let manga = try? await mangaRepo.getManga(id: item.mangaId),
               let chapter = try? await chapterRepo.getChapter(id: item.chapterId) {
                self.activeMangaForReading = manga
                self.activeChapterForReading = chapter
            }
        }
    }

    private func openMangaDetail(for item: ChapterUpdateItem) {
        Task { @MainActor in
            if let manga = try? await mangaRepo.getManga(id: item.mangaId) {
                self.selectedMangaForDetail = manga
            }
        }
    }

    private func toggleReadStatus(_ item: ChapterUpdateItem) {
        let newStatus = !item.read
        Task { @MainActor in
            try? await chapterRepo.updateProgress(chapterId: item.chapterId, lastPageRead: item.lastPageRead, isRead: newStatus, logHistory: false)
            if let idx = updates.firstIndex(where: { $0.chapterId == item.chapterId }) {
                updates[idx].read = newStatus
            }
        }
    }

    private func downloadChapter(_ item: ChapterUpdateItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId),
                  let chapter = try? await chapterRepo.getChapter(id: item.chapterId),
                  let src = extensionManager.getSource(id: item.sourceId) else { return }
            downloadManager.enqueue(manga: manga, chapters: [chapter], source: src)
        }
    }

    private func isDownloaded(_ item: ChapterUpdateItem) -> Bool {
        downloadManager.isChapterDownloaded(chapterId: item.chapterId, mangaId: item.mangaId)
    }

    private func groupUpdatesByDate(_ items: [ChapterUpdateItem]) -> [UpdateDateSection] {
        let calendar = Calendar.current
        var today: [ChapterUpdateItem] = []
        var yesterday: [ChapterUpdateItem] = []
        var thisWeek: [ChapterUpdateItem] = []
        var older: [ChapterUpdateItem] = []

        let now = Date()
        for item in items {
            let itemDate = item.dateUpload > Date(timeIntervalSince1970: 86400) ? item.dateUpload : item.dateFetch
            if calendar.isDateInToday(itemDate) {
                today.append(item)
            } else if calendar.isDateInYesterday(itemDate) {
                yesterday.append(item)
            } else if let daysAgo = calendar.dateComponents([.day], from: itemDate, to: now).day, daysAgo <= 7 {
                thisWeek.append(item)
            } else {
                older.append(item)
            }
        }

        var sections: [UpdateDateSection] = []
        if !today.isEmpty { sections.append(UpdateDateSection(title: "Today", items: today)) }
        if !yesterday.isEmpty { sections.append(UpdateDateSection(title: "Yesterday", items: yesterday)) }
        if !thisWeek.isEmpty { sections.append(UpdateDateSection(title: "Past 7 Days", items: thisWeek)) }
        if !older.isEmpty { sections.append(UpdateDateSection(title: "Older", items: older)) }
        return sections
    }
}

// MARK: - Subviews & Models

struct UpdateDateSection {
    let title: String
    let items: [ChapterUpdateItem]
}

struct UpdateRowView: View {
    let item: ChapterUpdateItem
    let isDownloaded: Bool
    let onRead: () -> Void
    let onDownload: () -> Void
    let onToggleRead: () -> Void
    let onViewManga: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Manga Cover Thumbnail
            AsyncImage(url: URL(string: item.effectiveThumbnailUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(YomiTheme.surface)
                        .overlay(Image(systemName: "book.closed").font(.caption).foregroundStyle(YomiTheme.textSecondary))
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .clipped()
            .onTapGesture {
                onViewManga()
            }

            // Title & Chapter Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.mangaTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.read {
                        Circle()
                            .fill(YomiTheme.unreadBadge)
                            .frame(width: 7, height: 7)
                    }

                    Text(item.displayChapterTitle)
                        .font(.caption)
                        .foregroundStyle(item.read ? YomiTheme.textSecondary : YomiTheme.textPrimary)
                        .lineLimit(1)
                }

                Text(formatDate(item.dateUpload))
                    .font(.caption2)
                    .foregroundStyle(YomiTheme.textSecondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onRead()
            }

            Spacer()

            // Download Status Action
            Button(action: onDownload) {
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.body)
                    .foregroundStyle(isDownloaded ? YomiTheme.downloadBadge : YomiTheme.textSecondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onRead()
            } label: {
                Label("Read Chapter", systemImage: "book.fill")
            }

            Button {
                onToggleRead()
            } label: {
                Label(item.read ? "Mark as Unread" : "Mark as Read", systemImage: item.read ? "envelope.badge" : "checkmark.circle")
            }

            Button {
                onDownload()
            } label: {
                Label("Download Chapter", systemImage: "arrow.down.circle")
            }

            Button {
                onViewManga()
            } label: {
                Label("View Manga Details", systemImage: "info.circle")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        guard date > Date(timeIntervalSince1970: 86400) else { return "Recently" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct EmptyUpdatesView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(YomiTheme.textSecondary)
            Text("No Recent Updates")
                .font(.headline)
                .foregroundStyle(YomiTheme.textPrimary)
            Text("New chapters from manga in your library will appear here.")
                .font(.subheadline)
                .foregroundStyle(YomiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                onRefresh()
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(YomiTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
            Spacer()
        }
    }
}
