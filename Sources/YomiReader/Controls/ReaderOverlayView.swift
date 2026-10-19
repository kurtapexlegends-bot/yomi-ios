import SwiftUI
import YomiCore

/// Floating HUD overlay providing chapter navigation, scrubber, and reader quick settings.
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

    public let onDismiss: () -> Void
    public let onNextChapter: () -> Void
    public let onPreviousChapter: () -> Void

    @State private var isShowingSettingsSheet: Bool = false

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
        self.onDismiss = onDismiss
        self.onNextChapter = onNextChapter
        self.onPreviousChapter = onPreviousChapter
    }

    public var body: some View {
        ZStack {
            if isHUDVisible {
                // Top Header Bar
                VStack {
                    HStack(spacing: 16) {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mangaTitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                            Text(chapterTitle)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            isShowingSettingsSheet.toggle()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 48)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)

                    Spacer()

                    // Bottom Navigation Bar
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button(action: onPreviousChapter) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }

                            Text("\(currentPage + 1) / \(max(1, totalPages))")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 60)

                            Slider(
                                value: Binding(
                                    get: { Double(min(max(0, currentPage), max(0, totalPages - 1))) },
                                    set: { currentPage = Int($0) }
                                ),
                                in: 0...Double(max(1, totalPages - 1)),
                                step: 1
                            )
                            .tint(.white)
                            .disabled(totalPages <= 1)

                            Button(action: onNextChapter) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHUDVisible)
        .sheet(isPresented: $isShowingSettingsSheet) {
            ReaderSettingsSheet(
                viewer: $viewer,
                isAutocropEnabled: $isAutocropEnabled,
                isInvertColorsEnabled: $isInvertColorsEnabled,
                customBrightness: $customBrightness,
                tapZoneLayout: $tapZoneLayout
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Modal sheet for reader customizations (viewer modes, autocrop, brightness, inversion).
public struct ReaderSettingsSheet: View {
    @Binding public var viewer: MangaViewer
    @Binding public var isAutocropEnabled: Bool
    @Binding public var isInvertColorsEnabled: Bool
    @Binding public var customBrightness: CGFloat
    @Binding public var tapZoneLayout: TapZoneLayout

    public var body: some View {
        NavigationStack {
            Form {
                Section("Reading Direction") {
                    Picker("Layout Mode", selection: $viewer) {
                        ForEach(MangaViewer.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("Tap Zones") {
                    Picker("Tap Navigation", selection: $tapZoneLayout) {
                        ForEach(TapZoneLayout.allCases, id: \.self) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                }

                Section("Image Enhancements") {
                    Toggle("Autocrop Borders", isOn: $isAutocropEnabled)
                    Toggle("Invert Colors (OLED Night)", isOn: $isInvertColorsEnabled)
                }

                Section("Brightness") {
                    HStack {
                        Image(systemName: "sun.min")
                        Slider(value: $customBrightness, in: 0.1...1.0)
                        Image(systemName: "sun.max")
                    }
                }
            }
            .navigationTitle("Reader Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
