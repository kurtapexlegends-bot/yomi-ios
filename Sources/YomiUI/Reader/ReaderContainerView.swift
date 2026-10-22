import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions
import YomiReader
import YomiSync

#if canImport(UIKit)
import UIKit

public struct ReaderContainerView: View {
    public let manga: Manga
    @State public var chapter: Chapter
    @Environment(\.dismiss) private var dismiss

    @State private var pages: [ReaderPage] = []
    @State private var currentPage: Int = 0
    @State private var isHUDVisible: Bool = true
    @State private var viewer: MangaViewer = .defaultViewer
    @State private var isAutocropEnabled: Bool = false
    @State private var isInvertColorsEnabled: Bool = false
    @State private var customBrightness: CGFloat = 1.0
    @State private var tapZoneLayout: TapZoneLayout = .leftRight
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var localSource: (any SourceProtocol)? = nil
    /// Set after an in-reader source migration. The immutable `manga` value still carries the
    /// old source ID, so page loading and chapter navigation must prefer this live source.
    @State private var sourceOverride: (any SourceProtocol)? = nil
    @State private var migratedManga: Manga? = nil
    @State private var allChapters: [Chapter] = []
    @State private var isBookmarked: Bool = false
    @State private var pageLoadGeneration: Int = 0
    @State private var pageLoadTask: Task<Void, Never>?
    @State private var completedChapterID: Int64?

    private let chapterRepo = ChapterRepository()
    private let trackRepo = TrackRepository()
    private let downloadManager = DownloadManager.shared
    private let extensionManager = ExtensionManager.shared
    private let cloudSync = CloudSyncCoordinator.shared
    private let privacyManager = PrivacyManager.shared

    public init(manga: Manga, chapter: Chapter) {
        self.manga = manga
        self._chapter = State(initialValue: chapter)

        let defaults = UserDefaults.standard
        let savedViewer = defaults.object(forKey: "yomi.reader.defaultViewer") as? Int
        let resolvedViewer: MangaViewer = manga.viewer != .defaultViewer
            ? manga.viewer
            : (savedViewer.flatMap(MangaViewer.init(rawValue:)) ?? .defaultViewer)

        let savedTapZone = defaults.object(forKey: "yomi.reader.tapZones") as? Int
        let resolvedTapZone = savedTapZone.flatMap(TapZoneLayout.init(rawValue:)) ?? .leftRight

        self._viewer = State(initialValue: resolvedViewer)
        self._isAutocropEnabled = State(initialValue: defaults.bool(forKey: "yomi.reader.autocrop"))
        self._isInvertColorsEnabled = State(initialValue: defaults.bool(forKey: "yomi.reader.invert"))
        self._customBrightness = State(
            initialValue: CGFloat(defaults.object(forKey: "yomi.reader.brightness") as? Double ?? 1.0)
        )
        self._tapZoneLayout = State(initialValue: resolvedTapZone)
        self._isBookmarked = State(initialValue: chapter.bookmark)
    }

    public var body: some View {
        readerContent
            .statusBarHidden(!isHUDVisible)
            .onAppear {
                loadChapters()
                loadPages()
            }
            .onDisappear {
                pageLoadTask?.cancel()
            }
            .onChange(of: currentPage) { _, newPage in
                handlePageChanged(to: newPage)
            }
    }

    /// Persist reader preferences at the point of change instead of stacking seven `onChange`
    /// modifiers on the body (which made Swift's type checker time out on complex reader views).
    private var viewerPreference: Binding<MangaViewer> {
        Binding(
            get: { self.viewer },
            set: { self.viewer = $0; UserDefaults.standard.set($0.rawValue, forKey: "yomi.reader.defaultViewer") }
        )
    }

    private var autocropPreference: Binding<Bool> {
        Binding(
            get: { self.isAutocropEnabled },
            set: { self.isAutocropEnabled = $0; UserDefaults.standard.set($0, forKey: "yomi.reader.autocrop") }
        )
    }

    private var invertPreference: Binding<Bool> {
        Binding(
            get: { self.isInvertColorsEnabled },
            set: { self.isInvertColorsEnabled = $0; UserDefaults.standard.set($0, forKey: "yomi.reader.invert") }
        )
    }

    private var brightnessPreference: Binding<CGFloat> {
        Binding(
            get: { self.customBrightness },
            set: { self.customBrightness = $0; UserDefaults.standard.set(Double($0), forKey: "yomi.reader.brightness") }
        )
    }

    private var tapZonePreference: Binding<TapZoneLayout> {
        Binding(
            get: { self.tapZoneLayout },
            set: { self.tapZoneLayout = $0; UserDefaults.standard.set($0.rawValue, forKey: "yomi.reader.tapZones") }
        )
    }

    @ViewBuilder
    private var readerContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ReaderLoadingStateView(chapterTitle: chapter.displayTitle)
            } else if !pages.isEmpty {
                readerSurface
                readerOverlay
            } else {
                ReaderEmptyStateView(
                    chapterTitle: chapter.displayTitle,
                    errorMessage: errorMessage,
                    isMangaDexSource: manga.sourceId == MangaDexSource.sourceId,
                    onRetry: { loadPages() },
                    onNextChapter: { goToNextChapter() },
                    onSwitchSource: { switchSourceToMangaPill() },
                    onClose: { dismiss() }
                )
            }
        }
    }

    /// `.defaultViewer` means "use this title's saved layout", not the reader controller's
    /// internal vertical fallback. Resolve it before handing the mode to UIKit.
    private var effectiveViewer: MangaViewer {
        guard viewer == .defaultViewer else { return viewer }
        return manga.viewer == .defaultViewer ? .vertical : manga.viewer
    }

    private var readerSurface: some View {
        ReaderBridgeView(
            pages: pages,
            source: sourceOverride ?? localSource ?? extensionManager.getSource(id: manga.sourceId),
            viewer: effectiveViewer,
            isAutocropEnabled: isAutocropEnabled,
            isInvertColorsEnabled: isInvertColorsEnabled,
            customBrightness: customBrightness,
            tapZoneLayout: tapZoneLayout,
            currentPageIndex: $currentPage,
            onToggleHUD: {
                withAnimation { isHUDVisible.toggle() }
            },
            onRequestNextChapter: {
                goToNextChapter()
            },
            onRequestPreviousChapter: {
                goToPreviousChapter()
            }
        )
        .ignoresSafeArea()
    }

    private var readerOverlay: some View {
        ReaderOverlayView(
            chapterTitle: chapter.displayTitle,
            mangaTitle: manga.title,
            currentPage: $currentPage,
            totalPages: pages.count,
            isHUDVisible: $isHUDVisible,
            viewer: viewerPreference,
            isAutocropEnabled: autocropPreference,
            isInvertColorsEnabled: invertPreference,
            customBrightness: brightnessPreference,
            tapZoneLayout: tapZonePreference,
            isBookmarked: $isBookmarked,
            chapters: allChapters,
            currentChapterId: chapter.id,
            onSelectChapter: { selected in
                selectChapter(selected)
            },
            onToggleBookmark: {
                toggleBookmark()
            },
            onDismiss: {
                dismiss()
            },
            onNextChapter: {
                goToNextChapter()
            },
            onPreviousChapter: {
                goToPreviousChapter()
            }
        )
    }



    private func loadPages() {
        pageLoadTask?.cancel()
        pageLoadGeneration += 1
        let generation = pageLoadGeneration
        var requestedChapter = chapter
        if requestedChapter.url.contains("mangakakalot") || requestedChapter.url.contains("mangakakalove") {
            requestedChapter.url = requestedChapter.url
                .replacingOccurrences(of: "://www.mangakakalot.com", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://mangakakalot.com", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://www.mangakakalot.gg", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://mangakakalot.gg", with: "://www.mangakakalove.com")
            if requestedChapter.url.contains("mangakakalove.com/chapter/") {
                requestedChapter.url = requestedChapter.url.replacingOccurrences(of: "mangakakalove.com/chapter/", with: "mangakakalove.com/manga/")
            }
        }

        isLoading = true
        localSource = nil
        pages = []
        errorMessage = nil

        pageLoadTask = Task { @MainActor in
            func isCurrent() -> Bool {
                generation == pageLoadGeneration
                    && !Task.isCancelled
                    && (chapter.id == requestedChapter.id || chapter.url == requestedChapter.url)
            }

            // Check if a downloaded .cbz archive exists.
            if let chId = requestedChapter.id, let mId = manga.id,
               let cbzURL = downloadManager.getDownloadedCBZURL(chapterId: chId, mangaId: mId),
               FileManager.default.fileExists(atPath: cbzURL.path) {
                if let local = try? LocalCBZSource(archiveURL: cbzURL), !local.pages.isEmpty {
                    guard isCurrent() else { return }
                    self.localSource = local
                    self.pages = local.pages
                    self.currentPage = max(0, min(requestedChapter.lastPageRead, local.pages.count - 1))
                    self.errorMessage = nil
                    self.isLoading = false
                    self.handlePageChanged(to: self.currentPage)
                    return
                }
            }

            // Fetch remote pages from the source.
            do {
                if let src = sourceOverride ?? extensionManager.getSource(id: manga.sourceId) {
                    let fetchedPages = try await src.getPageList(chapter: requestedChapter)
                    guard isCurrent() else { return }
                    if !fetchedPages.isEmpty {
                        self.pages = fetchedPages
                        self.currentPage = max(0, min(requestedChapter.lastPageRead, fetchedPages.count - 1))
                        self.errorMessage = nil
                    } else {
                        self.pages = []
                        self.errorMessage = "This chapter contains no hosted images on \(src.manifest.name)."
                    }
                } else {
                    guard isCurrent() else { return }
                    self.pages = []
                    self.errorMessage = "Source not found."
                }
            } catch {
                guard isCurrent() else { return }
                self.pages = []
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
            self.handlePageChanged(to: self.currentPage)
        }
    }

    private func handlePageChanged(to newPage: Int) {
        // `selectChapter` resets the page to zero before the next page list exists. Without this
        // guard that reset looked like "finished page 0" and marked the new chapter read.
        guard !isLoading, !pages.isEmpty, let chId = chapter.id else { return }
        let isComplete = newPage >= pages.count - 1
        if isComplete {
            guard completedChapterID != chId else { return }
            completedChapterID = chId
        }

        // Snapshot the current chapter: progress writes happen after awaits, and the user can
        // switch chapters while they are in flight.
        let chapterUrl = chapter.url
        let chapterNumber = chapter.chapterNumber
        let mangaUrl = migratedManga?.url ?? manga.url

        Task {
            if !privacyManager.isIncognitoMode {
                try? await chapterRepo.updateProgress(chapterId: chId, lastPageRead: newPage, isRead: isComplete)
                cloudSync.recordProgress(mangaUrl: mangaUrl, chapterUrl: chapterUrl, page: newPage, isRead: isComplete)

                if isComplete, chapter.id == chId {
                    autoDownloadNextChapter(completedChapterId: chId)
                }

                // Sync the linked AniList entry rather than guessing a media ID from the chapter number.
                if isComplete,
                   AniListClient.shared.isLoggedIn,
                   chapterNumber.isFinite,
                   let mangaId = manga.id,
                   let track = try? await trackRepo.getTrack(
                       mangaId: mangaId,
                       syncId: TrackerServiceType.aniList.rawValue
                   ) {
                    let progress = max(track.lastChapterRead, chapterNumber)
                    do {
                        try await AniListClient.shared.updateProgress(
                            mediaId: track.remoteId,
                            chapterProgress: Int(progress),
                            status: track.status,
                            score: track.score
                        )
                        // Keep the locally linked track in step so the detail screen and manual
                        // sync show the same progress that was pushed to AniList.
                        var updated = track
                        updated.lastChapterRead = progress
                        _ = try? await trackRepo.upsertTrack(updated)
                    } catch {
                        print("[Reader] AniList progress sync failed: \(error)")
                    }
                }
            }
        }
    }

    private func loadChapters() {
        guard let mangaId = manga.id else { return }
        Task { @MainActor in
            allChapters = (try? await chapterRepo.getChapters(forMangaId: mangaId)) ?? []
            if let refreshed = allChapters.first(where: { $0.id == chapter.id }) {
                chapter = refreshed
                isBookmarked = refreshed.bookmark
            }
        }
    }

    /// Honors Settings → Downloads → "Auto-download next chapter" when a chapter is finished.
    private func autoDownloadNextChapter(completedChapterId: Int64) {
        guard chapter.id == completedChapterId,
              UserDefaults.standard.bool(forKey: "yomi.download.autoNext"),
              let mangaId = manga.id,
              let source = sourceOverride ?? localSource ?? extensionManager.getSource(id: manga.sourceId),
              let index = allChapters.firstIndex(where: { $0.id == chapter.id || $0.url == chapter.url }),
              index > 0 else {
            return
        }

        let nextChapter = allChapters[index - 1]
        guard !nextChapter.read,
              let chapterId = nextChapter.id,
              !downloadManager.isChapterDownloaded(chapterId: chapterId, mangaId: mangaId) else {
            return
        }
        downloadManager.enqueue(manga: migratedManga ?? manga, chapters: [nextChapter], source: source)
    }

    private func selectChapter(_ selected: Chapter) {
        chapter = selected
        isBookmarked = selected.bookmark
        completedChapterID = nil
        currentPage = 0
        loadPages()
        if !allChapters.contains(where: { $0.id == selected.id }) {
            loadChapters()
        }
    }

    private func toggleBookmark() {
        guard let chapterId = chapter.id else { return }
        let newValue = !isBookmarked
        isBookmarked = newValue
        chapter.bookmark = newValue
        if let index = allChapters.firstIndex(where: { $0.id == chapterId }) {
            allChapters[index].bookmark = newValue
        }

        Task {
            try? await chapterRepo.setBookmark(chapterId: chapterId, isBookmarked: newValue)
        }
    }

    private func goToNextChapter() {
        if allChapters.isEmpty {
            loadChapters()
            return
        }
        guard let currentIdx = allChapters.firstIndex(where: { $0.id == chapter.id || $0.url == chapter.url }),
              currentIdx > 0 else { return }
        selectChapter(allChapters[currentIdx - 1])
    }

    private func goToPreviousChapter() {
        if allChapters.isEmpty {
            loadChapters()
            return
        }
        guard let currentIdx = allChapters.firstIndex(where: { $0.id == chapter.id || $0.url == chapter.url }),
              currentIdx < allChapters.count - 1 else { return }
        selectChapter(allChapters[currentIdx + 1])
    }

    private func switchSourceToMangaPill() {
        isLoading = true
        Task {
            do {
                let pillSource = MangaPillSource()
                let results = try await pillSource.searchManga(query: manga.title, filters: [], page: 1)
                let normalizedTitle = manga.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let exactMatch = results.mangas.first {
                    $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
                }
                if let target = exactMatch ?? results.mangas.first {
                    let tool = SourceMigrationTool(mangaRepo: MangaRepository(), chapterRepo: chapterRepo)
                    _ = try await tool.migrate(manga: manga, toTarget: target, targetSource: pillSource)

                    if let mangaId = manga.id,
                       let newChapters = try? await chapterRepo.getChapters(forMangaId: mangaId),
                       let firstCh = newChapters.first(where: { !$0.read }) ?? newChapters.first {
                        await MainActor.run {
                            var migrated = target
                            migrated.id = manga.id
                            self.migratedManga = migrated
                            self.sourceOverride = pillSource
                            self.allChapters = newChapters
                            self.chapter = firstCh
                            self.isBookmarked = firstCh.bookmark
                            self.completedChapterID = nil
                            self.currentPage = 0
                            self.loadPages()
                        }
                        return
                    }
                }
                await MainActor.run {
                    self.errorMessage = "Could not locate matching manga on MangaPill. Please search in Browse."
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to switch source: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
#else
public struct ReaderContainerView: View {
    public init(manga: Manga, chapter: Chapter) {}
    public var body: some View {
        Text("Reader is only supported on iOS")
    }
}
#endif
