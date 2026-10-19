import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

public struct MangaDetailView: View {
    @State public var manga: Manga
    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters: Bool = false
    @State private var isInLibrary: Bool = false
    @State private var activeChapterForReading: Chapter?
    @State private var isShowingTrackingSheet: Bool = false
    @State private var isShowingCategorySheet: Bool = false

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let downloadManager = DownloadManager.shared
    private let extensionManager = ExtensionManager.shared

    public init(manga: Manga) {
        self._manga = State(initialValue: manga)
        self._isInLibrary = State(initialValue: manga.inLibrary)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                MangaHeaderBanner(manga: manga)

                // Action Buttons Row
                HStack(spacing: 12) {
                    Button {
                        toggleLibraryStatus()
                    } label: {
                        Label(isInLibrary ? "In Library" : "Add to Library", systemImage: isInLibrary ? "heart.fill" : "heart")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isInLibrary ? YomiTheme.accent : YomiTheme.surface)
                            .foregroundStyle(isInLibrary ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let firstUnread = chapters.first(where: { !$0.read }) ?? chapters.first {
                        Button {
                            activeChapterForReading = firstUnread
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button {
                        downloadAllUnread()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(YomiTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)

                // Synopsis & Genres
                if let desc = manga.description, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .lineLimit(4)

                        if !manga.genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(manga.genres, id: \.self) { genre in
                                        Text(genre)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(YomiTheme.surface)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Chapters Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chapters (\(chapters.count))")
                            .font(.title3.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    if isLoadingChapters {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(chapters, id: \.stableId) { chapter in
                                ChapterRowView(
                                    chapter: chapter,
                                    isDownloaded: isChapterDownloaded(chapter),
                                    onTap: {
                                        activeChapterForReading = chapter
                                    },
                                    onToggleRead: {
                                        toggleChapterRead(chapter)
                                    },
                                    onToggleBookmark: {
                                        toggleChapterBookmark(chapter)
                                    },
                                    onDownload: {
                                        downloadChapter(chapter)
                                    }
                                )
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingCategorySheet = true
                    } label: {
                        Label("Edit Categories", systemImage: "folder")
                    }
                    Button {
                        isShowingTrackingSheet = true
                    } label: {
                        Label("Tracking", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            loadChapters()
        }
        #if os(iOS)
        .fullScreenCover(item: $activeChapterForReading) { chapter in
            ReaderContainerView(manga: manga, chapter: chapter)
        }
        #else
        .sheet(item: $activeChapterForReading) { chapter in
            ReaderContainerView(manga: manga, chapter: chapter)
        }
        #endif
        .onChange(of: activeChapterForReading) { oldVal, newVal in
            if oldVal != nil && newVal == nil {
                if let mangaId = manga.id {
                    Task {
                        self.chapters = (try? await chapterRepo.getChapters(forMangaId: mangaId)) ?? self.chapters
                    }
                }
            }
        }
    }

    private func loadChapters() {
        isLoadingChapters = true

        Task {
            var currentManga = manga
            if let existing = try? await mangaRepo.getManga(sourceId: currentManga.sourceId, url: currentManga.url) {
                currentManga = existing
                self.manga = existing
                self.isInLibrary = existing.inLibrary
            } else if currentManga.id == nil {
                if let saved = try? await mangaRepo.upsert(currentManga) {
                    currentManga = saved
                    self.manga = saved
                }
            }

            guard let mangaId = currentManga.id else {
                self.isLoadingChapters = false
                return
            }

            // First load from local database
            let localChapters = (try? await chapterRepo.getChapters(forMangaId: mangaId)) ?? []
            if !localChapters.isEmpty {
                self.chapters = localChapters
                self.isLoadingChapters = false
            }

            // Sync fresh from source
            if let src = extensionManager.getSource(id: currentManga.sourceId) {
                if let freshDetails = try? await src.getMangaDetails(manga: currentManga) {
                    self.manga = freshDetails
                    _ = try? await mangaRepo.upsert(freshDetails)
                }
                if let freshChapters = try? await src.getChapterList(manga: currentManga) {
                    self.chapters = (try? await chapterRepo.syncChapters(freshChapters, forMangaId: mangaId)) ?? freshChapters
                }
            }
            self.isLoadingChapters = false
        }
    }

    private func toggleLibraryStatus() {
        isInLibrary.toggle()
        Task {
            if manga.id == nil {
                if let saved = try? await mangaRepo.upsert(manga) {
                    self.manga = saved
                }
            }
            guard let id = manga.id else { return }
            try? await mangaRepo.setInLibrary(mangaId: id, inLibrary: isInLibrary)
        }
    }

    private func toggleChapterRead(_ chapter: Chapter) {
        guard let chId = chapter.id else { return }
        let newStatus = !chapter.read
        Task {
            try? await chapterRepo.updateProgress(chapterId: chId, lastPageRead: chapter.lastPageRead, isRead: newStatus, logHistory: false)
            if let idx = chapters.firstIndex(where: { $0.id == chId }) {
                chapters[idx].read = newStatus
            }
        }
    }

    private func toggleChapterBookmark(_ chapter: Chapter) {
        guard let chId = chapter.id else { return }
        let newBookmark = !chapter.bookmark
        Task {
            try? await chapterRepo.setBookmark(chapterId: chId, isBookmarked: newBookmark)
            if let idx = chapters.firstIndex(where: { $0.id == chId }) {
                chapters[idx].bookmark = newBookmark
            }
        }
    }

    private func isChapterDownloaded(_ chapter: Chapter) -> Bool {
        guard let chId = chapter.id, let mId = manga.id else { return false }
        return downloadManager.isChapterDownloaded(chapterId: chId, mangaId: mId)
    }

    private func downloadChapter(_ chapter: Chapter) {
        guard let src = extensionManager.getSource(id: manga.sourceId) else { return }
        downloadManager.enqueue(manga: manga, chapters: [chapter], source: src)
    }

    private func downloadAllUnread() {
        guard let src = extensionManager.getSource(id: manga.sourceId) else { return }
        let unreads = chapters.filter { !$0.read }
        downloadManager.enqueue(manga: manga, chapters: unreads, source: src)
    }
}

// MARK: - Subcomponents

struct MangaHeaderBanner: View {
    let manga: Manga

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: URL(string: manga.effectiveThumbnailUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(YomiTheme.surface)
                }
            }
            .frame(width: 110, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium))
            .shadow(radius: 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(.title3.bold())
                    .lineLimit(3)

                if let author = manga.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(manga.status.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

struct ChapterRowView: View {
    let chapter: Chapter
    let isDownloaded: Bool
    let onTap: () -> Void
    let onToggleRead: () -> Void
    let onToggleBookmark: () -> Void
    let onDownload: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.displayTitle)
                        .font(.subheadline.weight(chapter.read ? .regular : .semibold))
                        .foregroundStyle(chapter.read ? YomiTheme.textSecondary : YomiTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(chapter.dateUpload, style: .date)
                            .font(.caption2)
                            .foregroundStyle(YomiTheme.textSecondary)
                        if let scan = chapter.scanlator {
                            Text("• \(scan)")
                                .font(.caption2)
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                if chapter.bookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if isDownloaded {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onToggleRead) {
                Label(chapter.read ? "Mark as Unread" : "Mark as Read", systemImage: chapter.read ? "envelope.badge" : "checkmark.circle")
            }
            Button(action: onToggleBookmark) {
                Label(chapter.bookmark ? "Remove Bookmark" : "Bookmark", systemImage: "bookmark")
            }
            if !isDownloaded {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }
}
