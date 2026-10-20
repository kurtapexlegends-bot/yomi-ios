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

// MARK: - Chapter list

struct ReaderChapterListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [Chapter]
    let currentChapterId: Int64?
    let onSelect: (Chapter) -> Void

    @State private var searchText: String = ""

    private var filteredChapters: [Chapter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || ($0.scanlator?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ReaderPalette.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 6) {
                        searchField

                        ForEach(filteredChapters, id: \.stableId) { chapter in
                            chapterRow(chapter)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Chapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ReaderPalette.violetBright)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            TextField("Find a chapter", text: $searchText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.38))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(ReaderPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 5)
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == currentChapterId
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "play.circle.fill" : chapter.read ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? ReaderPalette.violetBright : chapter.read ? ReaderPalette.green : .white.opacity(0.28))

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.84))
                        .lineLimit(1)
                    if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                        Text(scanlator)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if chapter.bookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ReaderPalette.gold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrent ? ReaderPalette.violet.opacity(0.20) : ReaderPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? ReaderPalette.violet.opacity(0.50) : .white.opacity(0.05), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings

/// Reader settings in a custom dark sheet instead of a system form.
public struct ReaderSettingsSheet: View {
    @Binding public var viewer: MangaViewer
    @Binding public var isAutocropEnabled: Bool
    @Binding public var isInvertColorsEnabled: Bool
    @Binding public var customBrightness: CGFloat
    @Binding public var tapZoneLayout: TapZoneLayout

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                ReaderPalette.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        settingsSection("Reading mode") {
                            ForEach(MangaViewer.allCases, id: \.self) { mode in
                                optionRow(
                                    title: mode.title,
                                    subtitle: modeSubtitle(mode),
                                    icon: modeIcon(mode),
                                    isSelected: viewer == mode
                                ) {
                                    viewer = mode
                                }
                            }
                        }

                        settingsSection("Tap zones") {
                            ForEach(TapZoneLayout.allCases, id: \.self) { layout in
                                optionRow(
                                    title: layout.title,
                                    subtitle: nil,
                                    icon: "hand.tap",
                                    isSelected: tapZoneLayout == layout
                                ) {
                                    tapZoneLayout = layout
                                }
                            }
                        }

                        settingsSection("Image") {
                            toggleRow("Autocrop borders", icon: "crop", isOn: $isAutocropEnabled)
                            toggleRow("Invert colors (OLED night)", icon: "circle.lefthalf.filled", isOn: $isInvertColorsEnabled)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Brightness", systemImage: "sun.max")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                    Spacer()
                                    Text("\(Int(customBrightness * 100))%")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                HStack(spacing: 8) {
                                    Image(systemName: "sun.min")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.35))
                                    Slider(value: $customBrightness, in: 0.1...1.0)
                                        .tint(ReaderPalette.violetBright)
                                    Image(systemName: "sun.max.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                        }

                        Button {
                            viewer = .defaultViewer
                            tapZoneLayout = .leftRight
                            isAutocropEnabled = false
                            isInvertColorsEnabled = false
                            customBrightness = 1.0
                        } label: {
                            Text("Reset reader settings")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(ReaderPalette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Reader")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ReaderPalette.violetBright)
                }
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(ReaderPalette.violetBright.opacity(0.8))

            VStack(spacing: 1) {
                content()
            }
            .background(ReaderPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func optionRow(title: String, subtitle: String?, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? ReaderPalette.violetBright : .white.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? ReaderPalette.violet.opacity(0.20) : .white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.90))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ReaderPalette.violetBright)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.90))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ReaderPalette.violet)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private func modeIcon(_ mode: MangaViewer) -> String {
        switch mode {
        case .defaultViewer: return "book"
        case .leftToRight: return "arrow.right"
        case .rightToLeft: return "arrow.left"
        case .vertical: return "arrow.up.arrow.down"
        case .webtoon: return "rectangle.portrait"
        case .continuousHorizontal: return "arrow.left.and.right"
        }
    }

    private func modeSubtitle(_ mode: MangaViewer) -> String {
        switch mode {
        case .defaultViewer: return "Use the title's own layout preference"
        case .leftToRight: return "Pages advance to the right"
        case .rightToLeft: return "Traditional manga direction"
        case .vertical: return "Paged vertical layout"
        case .webtoon: return "Continuous vertical strip"
        case .continuousHorizontal: return "Continuous horizontal strip"
        }
    }
}

// MARK: - Palette

private enum ReaderPalette {
    static let background = Color(red: 0.016, green: 0.016, blue: 0.024)
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.095)
    static let violet = Color(red: 0.486, green: 0.361, blue: 0.988)
    static let violetBright = Color(red: 0.60, green: 0.49, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let green = Color(red: 0.29, green: 0.84, blue: 0.52)
}
