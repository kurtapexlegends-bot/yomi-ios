import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions
import YomiReader
import YomiSync

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
                VStack(spacing: 12) {
                    Text("No Pages Found")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
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
            if let src = extensionManager.getSource(id: manga.sourceId) {
                if let fetchedPages = try? await src.getPageList(chapter: chapter) {
                    self.pages = fetchedPages
                    self.currentPage = min(chapter.lastPageRead, fetchedPages.count - 1)
                }
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
        // Fetch adjacent next chapter
    }

    private func goToPreviousChapter() {
        // Fetch adjacent previous chapter
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
