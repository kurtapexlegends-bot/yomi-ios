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

    private let chapterRepo = ChapterRepository()
    private let downloadManager = DownloadManager.shared
    private let extensionManager = ExtensionManager.shared
    private let cloudSync = CloudSyncCoordinator.shared
    private let privacyManager = PrivacyManager.shared

    public init(manga: Manga, chapter: Chapter) {
        self.manga = manga
        self._chapter = State(initialValue: chapter)
        self._viewer = State(initialValue: manga.viewer)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading Chapter...")
                    .foregroundStyle(.white)
            } else if !pages.isEmpty {
                ReaderBridgeView(
                    pages: pages,
                    source: extensionManager.getSource(id: manga.sourceId),
                    viewer: viewer,
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

                ReaderOverlayView(
                    chapterTitle: chapter.displayTitle,
                    mangaTitle: manga.title,
                    currentPage: $currentPage,
                    totalPages: pages.count,
                    isHUDVisible: $isHUDVisible,
                    viewer: $viewer,
                    isAutocropEnabled: $isAutocropEnabled,
                    isInvertColorsEnabled: $isInvertColorsEnabled,
                    customBrightness: $customBrightness,
                    tapZoneLayout: $tapZoneLayout,
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
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(YomiTheme.accent)

                    Text("No Pages Available")
                        .font(.headline.bold())
                        .foregroundStyle(.white)

                    Text(errorMessage ?? "The source does not host readable pages for \(chapter.displayTitle). It may be an external release or temporarily offline.")
                        .font(.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 12) {
                        Button {
                            loadPages()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(YomiTheme.accent)

                        if manga.sourceId == MangaDexSource.sourceId {
                            Button {
                                switchSourceToMangaPill()
                            } label: {
                                Label("Read on MangaPill", systemImage: "arrow.triangle.swap")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        } else {
                            Button {
                                goToNextChapter()
                            } label: {
                                Label("Next Chapter", systemImage: "forward.fill")
                                    .font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(YomiTheme.accent)
                        }
                    }

                    Button("Close") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .padding(.top, 4)
                }
                .padding(24)
            }
        }
        .statusBarHidden(!isHUDVisible)
        .onAppear {
            loadPages()
        }
        .onChange(of: currentPage) { _, newPage in
            handlePageChanged(to: newPage)
        }
    }

    private func loadPages() {
        isLoading = true
        Task {
            // Check if downloaded .cbz archive exists
            if let chId = chapter.id, let mId = manga.id,
               let cbzURL = downloadManager.getDownloadedCBZURL(chapterId: chId, mangaId: mId),
               FileManager.default.fileExists(atPath: cbzURL.path) {
                if let localPages = try? CBZArchiver.readCBZPages(from: cbzURL), !localPages.isEmpty {
                    self.pages = localPages
                    self.currentPage = min(chapter.lastPageRead, localPages.count - 1)
                    self.isLoading = false
                    return
                }
            }

            // Fetch remote pages from source
            do {
                if let src = extensionManager.getSource(id: manga.sourceId) {
                    let fetchedPages = try await src.getPageList(chapter: chapter)
                    if !fetchedPages.isEmpty {
                        self.pages = fetchedPages
                        self.currentPage = min(chapter.lastPageRead, fetchedPages.count - 1)
                        self.errorMessage = nil
                    } else {
                        self.pages = []
                        self.errorMessage = "This chapter contains no hosted images on \(src.manifest.name)."
                    }
                } else {
                    self.pages = []
                    self.errorMessage = "Source not found."
                }
            } catch {
                self.pages = []
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    private func handlePageChanged(to newPage: Int) {
        guard let chId = chapter.id else { return }
        let isComplete = newPage >= pages.count - 1

        Task {
            if !privacyManager.isIncognitoMode {
                try? await chapterRepo.updateProgress(chapterId: chId, lastPageRead: newPage, isRead: isComplete)
                cloudSync.recordProgress(mangaUrl: manga.url, chapterUrl: chapter.url, page: newPage, isRead: isComplete)

                // Sync to AniList if chapter completed
                if isComplete && AniListClient.shared.isLoggedIn {
                    try? await AniListClient.shared.updateProgress(
                        mediaId: Int64(chapter.chapterNumber),
                        chapterProgress: Int(chapter.chapterNumber),
                        status: .reading,
                        score: 0.0
                    )
                }
            }
        }
    }

    private func goToNextChapter() {
        guard let mId = manga.id else { return }
        Task {
            let allChapters = (try? await chapterRepo.getChapters(forMangaId: mId)) ?? []
            if let currentIdx = allChapters.firstIndex(where: { $0.url == chapter.url }) {
                // Chapters are sorted descending (latest first); next chronological is previous index
                if currentIdx > 0 {
                    let nextCh = allChapters[currentIdx - 1]
                    await MainActor.run {
                        self.chapter = nextCh
                        self.currentPage = 0
                        loadPages()
                    }
                }
            }
        }
    }

    private func goToPreviousChapter() {
        guard let mId = manga.id else { return }
        Task {
            let allChapters = (try? await chapterRepo.getChapters(forMangaId: mId)) ?? []
            if let currentIdx = allChapters.firstIndex(where: { $0.url == chapter.url }) {
                if currentIdx < allChapters.count - 1 {
                    let prevCh = allChapters[currentIdx + 1]
                    await MainActor.run {
                        self.chapter = prevCh
                        self.currentPage = 0
                        loadPages()
                    }
                }
            }
        }
    }

    private func switchSourceToMangaPill() {
        isLoading = true
        Task {
            do {
                let pillSource = MangaPillSource()
                let results = try await pillSource.searchManga(query: manga.title, filters: [], page: 1)
                if let target = results.mangas.first {
                    let tool = SourceMigrationTool(mangaRepo: MangaRepository(), chapterRepo: chapterRepo)
                    _ = try await tool.migrate(manga: manga, toTarget: target, targetSource: pillSource)
                    if let newChapters = try? await chapterRepo.getChapters(forMangaId: manga.id ?? 0),
                       let firstCh = newChapters.first(where: { !$0.read }) ?? newChapters.first {
                        await MainActor.run {
                            self.chapter = firstCh
                            self.currentPage = 0
                            loadPages()
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

// MARK: - UIViewControllerRepresentable Bridge

struct ReaderBridgeView: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let source: (any SourceProtocol)?
    let viewer: MangaViewer
    let isAutocropEnabled: Bool
    let isInvertColorsEnabled: Bool
    let customBrightness: CGFloat
    let tapZoneLayout: TapZoneLayout
    @Binding var currentPageIndex: Int

    let onToggleHUD: () -> Void
    let onRequestNextChapter: () -> Void
    let onRequestPreviousChapter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ReaderViewController {
        let vc = ReaderViewController()
        vc.source = source
        vc.delegate = context.coordinator
        vc.pages = pages
        vc.viewer = viewer
        vc.isAutocropEnabled = isAutocropEnabled
        vc.isInvertColorsEnabled = isInvertColorsEnabled
        vc.customBrightness = customBrightness
        vc.tapZoneLayout = tapZoneLayout
        return vc
    }

    func updateUIViewController(_ uiViewController: ReaderViewController, context: Context) {
        uiViewController.source = source
        uiViewController.viewer = viewer
        uiViewController.isAutocropEnabled = isAutocropEnabled
        uiViewController.isInvertColorsEnabled = isInvertColorsEnabled
        uiViewController.customBrightness = customBrightness
        uiViewController.tapZoneLayout = tapZoneLayout

        // Synchronize page list when chapter updates
        if uiViewController.pages.map(\.url) != pages.map(\.url) {
            uiViewController.pages = pages
            uiViewController.scrollToPage(index: currentPageIndex, animated: false)
        } else if uiViewController.currentPageIndex != currentPageIndex {
            // Synchronize HUD scrubber scrub position
            uiViewController.scrollToPage(index: currentPageIndex, animated: false)
        }
    }

    final class Coordinator: NSObject, ReaderViewControllerDelegate {
        var parent: ReaderBridgeView

        init(_ parent: ReaderBridgeView) {
            self.parent = parent
        }

        func readerViewController(_ controller: ReaderViewController, didChangePage pageIndex: Int, totalPages: Int) {
            DispatchQueue.main.async {
                self.parent.currentPageIndex = pageIndex
            }
        }

        func readerViewControllerDidToggleHUD(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onToggleHUD()
            }
        }

        func readerViewControllerRequestsNextChapter(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onRequestNextChapter()
            }
        }

        func readerViewControllerRequestsPreviousChapter(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onRequestPreviousChapter()
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
