import SwiftUI
import YomiCore

// MARK: - Reader settings sheet

public struct ReaderSettingsSheet: View {
    @Binding public var viewer: MangaViewer
    @Binding public var isAutocropEnabled: Bool
    @Binding public var isInvertColorsEnabled: Bool
    @Binding public var customBrightness: CGFloat
    @Binding public var tapZoneLayout: TapZoneLayout

    @Environment(\.dismiss) private var dismiss

    public init(
        viewer: Binding<MangaViewer>,
        isAutocropEnabled: Binding<Bool>,
        isInvertColorsEnabled: Binding<Bool>,
        customBrightness: Binding<CGFloat>,
        tapZoneLayout: Binding<TapZoneLayout>
    ) {
        self._viewer = viewer
        self._isAutocropEnabled = isAutocropEnabled
        self._isInvertColorsEnabled = isInvertColorsEnabled
        self._customBrightness = customBrightness
        self._tapZoneLayout = tapZoneLayout
    }

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
