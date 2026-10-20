import SwiftUI
import YomiCore

/// Reader HUD with a clear top bar, page scrubber, chapter switcher, bookmarking,
/// and a fully custom settings sheet. It deliberately avoids system `Form` chrome so
/// the reader keeps its edge-to-edge, distraction-free character.
public struct ReaderOverlayView: View {
    public let chapterTitle: String
    public let mangaTitle: String
    @Binding public var currentPage: Int
    public let totalPages: Int
    @Binding public var isHUDVisible: Bool
    @Binding public var viewer: MangaViewer
    @Binding public var isAutocropEnabled: Bool
    @Binding public var isInvertColorsEnabled: Bool
    @Binding public var customBrightness: CGFloat
    @Binding public var tapZoneLayout: TapZoneLayout
    @Binding public var isBookmarked: Bool

    public let chapters: [Chapter]
    public let currentChapterId: Int64?
    public let onSelectChapter: (Chapter) -> Void
    public let onToggleBookmark: () -> Void
    public let onDismiss: () -> Void
    public let onNextChapter: () -> Void
    public let onPreviousChapter: () -> Void

    @State private var isShowingSettingsSheet: Bool = false
    @State private var isShowingChapterList: Bool = false

    public init(
        chapterTitle: String,
        mangaTitle: String,
        currentPage: Binding<Int>,
        totalPages: Int,
        isHUDVisible: Binding<Bool>,
        viewer: Binding<MangaViewer>,
        isAutocropEnabled: Binding<Bool>,
        isInvertColorsEnabled: Binding<Bool>,
        customBrightness: Binding<CGFloat>,
        tapZoneLayout: Binding<TapZoneLayout>,
        isBookmarked: Binding<Bool>,
        chapters: [Chapter],
        currentChapterId: Int64?,
        onSelectChapter: @escaping (Chapter) -> Void,
        onToggleBookmark: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onNextChapter: @escaping () -> Void,
        onPreviousChapter: @escaping () -> Void
    ) {
        self.chapterTitle = chapterTitle
        self.mangaTitle = mangaTitle
        self._currentPage = currentPage
        self.totalPages = totalPages
        self._isHUDVisible = isHUDVisible
        self._viewer = viewer
        self._isAutocropEnabled = isAutocropEnabled
        self._isInvertColorsEnabled = isInvertColorsEnabled
        self._customBrightness = customBrightness
        self._tapZoneLayout = tapZoneLayout
        self._isBookmarked = isBookmarked
        self.chapters = chapters
        self.currentChapterId = currentChapterId
        self.onSelectChapter = onSelectChapter
        self.onToggleBookmark = onToggleBookmark
        self.onDismiss = onDismiss
        self.onNextChapter = onNextChapter
        self.onPreviousChapter = onPreviousChapter
    }

    private var pageCount: Int { max(1, totalPages) }
    private var safePage: Int { min(max(0, currentPage), max(0, pageCount - 1)) }

    private var currentChapterIndex: Int? {
        guard let currentChapterId else { return nil }
        return chapters.firstIndex {
            $0.id == currentChapterId || $0.stableId == "ch_\(currentChapterId)"
        }
    }

    private var chapterPosition: String {
        guard let index = currentChapterIndex else { return chapterTitle }
        return "Chapter \(chapters.count - index) of \(chapters.count)"
    }

    private var canGoToNextChapter: Bool {
        guard let index = currentChapterIndex else { return false }
        return index > 0
    }

    private var canGoToPreviousChapter: Bool {
        guard let index = currentChapterIndex else { return false }
        return index < chapters.count - 1
    }

    public var body: some View {
        ZStack {
            if isHUDVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHUDVisible)
        .sheet(isPresented: $isShowingSettingsSheet) {
            ReaderSettingsSheet(
                viewer: $viewer,
                isAutocropEnabled: $isAutocropEnabled,
                isInvertColorsEnabled: $isInvertColorsEnabled,
                customBrightness: $customBrightness,
                tapZoneLayout: $tapZoneLayout
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingChapterList) {
            ReaderChapterListSheet(
                chapters: chapters,
                currentChapterId: currentChapterId,
                onSelect: { chapter in
                    isShowingChapterList = false
                    onSelectChapter(chapter)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 11) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close reader")

            VStack(alignment: .leading, spacing: 2) {
                Text(mangaTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Text(chapterTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onToggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isBookmarked ? ReaderPalette.gold : .white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark chapter")

            Button {
                isShowingSettingsSheet = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reader settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.88), .black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 12) {
            pageScrubber

            HStack(spacing: 10) {
                Button(action: onPreviousChapter) {
                    HStack(spacing: 6) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Prev")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canGoToPreviousChapter)
                .opacity(canGoToPreviousChapter ? 1 : 0.38)

                Button {
                    isShowingChapterList = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                        Text(chapterPosition)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(ReaderPalette.violet.opacity(0.34))
                    .overlay(Capsule().stroke(ReaderPalette.violet.opacity(0.55), lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onNextChapter) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.white.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNextChapter)
                .opacity(canGoToNextChapter ? 1 : 0.38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.62), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var pageScrubber: some View {
        VStack(spacing: 7) {
            HStack {
                Text("PAGE \(safePage + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.52))
                Spacer()
                Text("\(safePage + 1) / \(pageCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { Double(safePage) },
                    set: { newValue in
                        currentPage = Int(newValue.rounded())
                    }
                ),
                in: 0...Double(max(1, pageCount - 1)),
                step: 1
            )
            .tint(ReaderPalette.violetBright)
            .disabled(totalPages <= 1)
        }
    }
}

// MARK: - Palette

enum ReaderPalette {
    static let background = Color(red: 0.016, green: 0.016, blue: 0.024)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.095)
    static let violet = Color(red: 0.486, green: 0.361, blue: 0.988)
    static let violetBright = Color(red: 0.60, green: 0.49, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let green = Color(red: 0.29, green: 0.84, blue: 0.52)
}
