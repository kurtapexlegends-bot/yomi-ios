import SwiftUI
import YomiCore
import YomiReader
import YomiSync
import YomiDownload
import YomiExtensions
import YomiDatabase

/// Unified application settings hub with Inset Grouped styling on True OLED Black canvas.
public struct SettingsView: View {
    @State private var biometricManager = BiometricSecurityManager.shared
    @State private var privacyManager = PrivacyManager.shared
    @State private var extensionManager = ExtensionManager.shared

    @AppStorage("yomi.reader.defaultViewer") private var defaultViewerRaw: Int = MangaViewer.defaultViewer.rawValue
    @AppStorage("yomi.reader.autocrop") private var isAutocropEnabled: Bool = false
    @AppStorage("yomi.reader.invert") private var isInvertColorsEnabled: Bool = false
    @AppStorage("yomi.reader.tapZones") private var tapZoneRaw: Int = TapZoneLayout.leftRight.rawValue
    @AppStorage("yomi.reader.brightness") private var readerBrightness: Double = 1.0
    @AppStorage("yomi.download.wifiOnly") private var downloadOnlyOnWifi: Bool = true
    @AppStorage("yomi.download.autoNext") private var autoDownloadNextChapters: Bool = false
    @AppStorage("yomi.library.layout") private var libraryLayout: String = "grid"

    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingAniListAlert: Bool = false
    @State private var aniListTokenInput: String = ""
    @State private var statusToast: String?
    @State private var exportedBackupURL: URL?
    @State private var isShowingClearCacheAlert: Bool = false
    @State private var isShowingRebuildFTSAlert: Bool = false
    @State private var isShowingResetWebDataAlert: Bool = false
    @State private var storageUsed: Int64 = 0
    @State private var downloadedCount: Int = 0

    private let downloadManager = DownloadManager.shared

    public init() {}

    private var viewerBinding: Binding<MangaViewer> {
        Binding(
            get: { MangaViewer(rawValue: defaultViewerRaw) ?? .defaultViewer },
            set: { defaultViewerRaw = $0.rawValue }
        )
    }

    private var tapZoneBinding: Binding<TapZoneLayout> {
        Binding(
            get: { TapZoneLayout(rawValue: tapZoneRaw) ?? .leftRight },
            set: { tapZoneRaw = $0.rawValue }
        )
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        appearanceSection
                        readerSection
                        librarySection
                        sourcesSection
                        downloadsSection
                        trackingSection
                        securitySection
                        backupSection
                        advancedSection
                        aboutSection
                    }
                    .padding(.horizontal, YomiTheme.contentPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { refreshStorage() }
            .onChange(of: downloadOnlyOnWifi) { _, isEnabled in
                if !isEnabled { downloadManager.processQueuedJobs() }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result: result)
            }
            .alert("Connect AniList", isPresented: $isShowingAniListAlert) {
                TextField("Paste AniList access token", text: $aniListTokenInput)
                Button("Save") {
                    AniListClient.shared.accessToken = aniListTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    aniListTokenInput = ""
                    statusToast = "AniList connected."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Generate an access token in your AniList settings, then paste it here.")
            }
            .alert("Purge Image Memory Cache", isPresented: $isShowingClearCacheAlert) {
                Button("Purge", role: .destructive) {
                    ImageDownsampler.shared.purgeMemory()
                    statusToast = "Decoded image memory cleared."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears in-memory decoded image textures. Downloaded chapters remain intact.")
            }
            .alert("Rebuild Search Index", isPresented: $isShowingRebuildFTSAlert) {
                Button("Rebuild", role: .destructive) { rebuildFTSIndex() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Re-indexes library titles for fast local search.")
            }
            .alert("Reset Cloudflare Sessions", isPresented: $isShowingResetWebDataAlert) {
                Button("Reset", role: .destructive) {
                    CloudflareSolver.shared.resetVerification()
                    statusToast = "Cloudflare sessions cleared."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears cached clearance cookies so sources will re-verify on next challenge.")
            }
            .overlay(alignment: .bottom) {
                if let toast = statusToast {
                    Text(toast)
                        .font(YomiFont.caption.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(YomiTheme.elevatedSurface)
                        .overlay(Capsule().stroke(YomiTheme.borderStrong, lineWidth: 0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { statusToast = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        SettingsGroup("Appearance") {
            SettingsInfoRow(icon: "moon.fill", tint: YomiTheme.accentStrong, title: "Theme", value: "OLED Black")
            divider
            HStack(spacing: 12) {
                SettingsIcon("paintpalette.fill", tint: YomiTheme.accentStrong)
                Text("Accent")
                    .font(YomiFont.body)
                    .foregroundStyle(YomiTheme.textPrimary)
                Spacer()
                Circle().fill(YomiTheme.accent).frame(width: 16, height: 16)
            }
            .padding(.vertical, 10)
            divider
            Picker(selection: $libraryLayout) {
                Text("Grid").tag("grid")
                Text("List").tag("list")
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("square.grid.2x2.fill", tint: YomiTheme.unreadBadge)
                    Text("Library Layout")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .tint(YomiTheme.accentStrong)
            .padding(.vertical, 2)
        }
    }

    private var readerSection: some View {
        SettingsGroup("Reader Engine") {
            Picker(selection: viewerBinding) {
                ForEach(MangaViewer.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("book.pages.fill", tint: YomiTheme.unreadBadge)
                    Text("Default Reading Mode")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .tint(YomiTheme.accentStrong)
            .padding(.vertical, 2)
            divider
            Picker(selection: tapZoneBinding) {
                ForEach(TapZoneLayout.allCases, id: \.self) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("hand.tap.fill", tint: YomiTheme.warning)
                    Text("Tap Navigation")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .tint(YomiTheme.accentStrong)
            .padding(.vertical, 2)
            divider
            SettingsToggleRow(icon: "crop", tint: YomiTheme.success, title: "Autocrop Page Borders", isOn: $isAutocropEnabled)
            divider
            SettingsToggleRow(icon: "circle.righthalf.filled", tint: YomiTheme.accentStrong, title: "Invert Colors (Dark Mode Pages)", isOn: $isInvertColorsEnabled)
            divider
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    SettingsIcon("sun.max.fill", tint: YomiTheme.warning)
                    Text("Reader Brightness")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Text("\(Int(readerBrightness * 100))%")
                        .font(YomiFont.number)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Slider(value: $readerBrightness, in: 0.1...1.0)
                    .tint(YomiTheme.accent)
                    .padding(.leading, 38)
            }
            .padding(.vertical, 6)
        }
    }

    private var librarySection: some View {
        SettingsGroup("Library") {
            NavigationLink {
                CategoryManagerView()
            } label: {
                SettingsNavigationRow(icon: "folder.fill", tint: YomiTheme.warning, title: "Manage Categories", value: "")
            }
            divider
            NavigationLink {
                StatisticsView()
            } label: {
                SettingsNavigationRow(icon: "chart.bar.fill", tint: YomiTheme.unreadBadge, title: "Reading Statistics", value: "Local only")
            }
        }
    }

    private var sourcesSection: some View {
        SettingsGroup("Sources & Extensions") {
            NavigationLink {
                ExtensionStoreView()
            } label: {
                SettingsNavigationRow(
                    icon: "puzzlepiece.extension.fill",
                    tint: YomiTheme.accentStrong,
                    title: "Extension Catalog",
                    value: "\(extensionManager.installedSources.count) installed"
                )
            }
            divider
            Button {
                isShowingResetWebDataAlert = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("arrow.counterclockwise", tint: YomiTheme.warning)
                    Text("Reset Cloudflare Clearance")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var downloadsSection: some View {
        SettingsGroup("Downloads") {
            NavigationLink {
                DownloadsView()
            } label: {
                SettingsNavigationRow(
                    icon: "arrow.down.circle.fill",
                    tint: YomiTheme.success,
                    title: "Downloaded Chapters",
                    value: "\(downloadedCount) (\(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file)))"
                )
            }
            divider
            SettingsToggleRow(icon: "wifi", tint: YomiTheme.success, title: "Download Only on Wi-Fi", isOn: $downloadOnlyOnWifi)
            divider
            SettingsToggleRow(icon: "arrow.down.to.line.compact", tint: YomiTheme.unreadBadge, title: "Auto-Download Next Chapter", isOn: $autoDownloadNextChapters)
            divider
            Button {
                isShowingClearCacheAlert = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("memorychip", tint: YomiTheme.danger)
                    Text("Clear Image Cache")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var securitySection: some View {
        SettingsGroup("Security & Privacy") {
            SettingsToggleRow(icon: "lock.shield.fill", tint: YomiTheme.danger, title: "Biometric App Lock", isOn: $biometricManager.isAppLockEnabled)
            divider
            SettingsToggleRow(
                icon: "eye.slash.fill",
                tint: YomiTheme.accentStrong,
                title: "Incognito Mode",
                isOn: Binding(
                    get: { privacyManager.isIncognitoMode },
                    set: { _ in privacyManager.toggleIncognito() }
                )
            )
            divider
            SettingsToggleRow(icon: "square.dashed", tint: YomiTheme.textSecondary, title: "Hide App in App Switcher", isOn: $privacyManager.isSnapshotProtectionEnabled)
        }
    }

    private var trackingSection: some View {
        SettingsGroup("Tracking") {
            HStack(spacing: 12) {
                SettingsIcon("arrow.triangle.2.circlepath", tint: YomiTheme.unreadBadge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AniList")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(AniListClient.shared.isLoggedIn ? "Connected" : "Disconnected")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Spacer()
                if AniListClient.shared.isLoggedIn {
                    Button("Disconnect") {
                        AniListClient.shared.accessToken = nil
                        statusToast = "AniList disconnected."
                    }
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(YomiTheme.danger)
                } else {
                    Button("Connect") { isShowingAniListAlert = true }
                        .font(YomiFont.caption.weight(.semibold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var backupSection: some View {
        SettingsGroup("Backup & Restore") {
            Button {
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("arrow.counterclockwise", tint: YomiTheme.accentStrong)
                    Text("Restore Backup (.tachibk)")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(YomiTheme.textTertiary)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            divider
            Button {
                exportTachiyomiBackup()
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("square.and.arrow.up", tint: YomiTheme.warning)
                    Text("Export Library Backup")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            if let exportedBackupURL {
                divider
                ShareLink(item: exportedBackupURL) {
                    HStack(spacing: 12) {
                        SettingsIcon("doc.badge.arrow.up", tint: YomiTheme.success)
                        Text("Share Exported File")
                            .font(YomiFont.body)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var advancedSection: some View {
        SettingsGroup("Advanced") {
            Button {
                isShowingRebuildFTSAlert = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIcon("magnifyingglass.circle.fill", tint: YomiTheme.warning)
                    Text("Rebuild Full-Text Search Index")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        SettingsGroup("About") {
            NavigationLink {
                AboutView()
            } label: {
                SettingsNavigationRow(icon: "info.circle.fill", tint: YomiTheme.textSecondary, title: "About Yomi", value: "1.0.0")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(YomiTheme.border).frame(height: 0.5)
    }

    // MARK: - Actions

    private func refreshStorage() {
        let files = downloadManager.listDownloadedChapterFiles()
        downloadedCount = files.count
        storageUsed = files.reduce(0) { $0 + $1.byteCount }
    }

    private func handleBackupImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            Task {
                do {
                    let counts = try await TachibkManager.shared.restoreBackup(from: fileURL)
                    statusToast = "Restored \(counts.restoredMangas) titles, \(counts.restoredChapters) chapters."
                } catch {
                    statusToast = "Restore failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            statusToast = "File error: \(error.localizedDescription)"
        }
    }

    private func exportTachiyomiBackup() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let exportURL = tempDir.appendingPathComponent("yomi_\(Int(Date().timeIntervalSince1970)).tachibk")
                try await TachibkManager.shared.exportBackup(to: exportURL)
                exportedBackupURL = exportURL
                statusToast = "Backup ready."
            } catch {
                statusToast = "Backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func rebuildFTSIndex() {
        Task {
            do {
                try await MangaRepository().rebuildFTSIndex()
                statusToast = "Search index rebuilt."
            } catch {
                statusToast = "Rebuild failed: \(error.localizedDescription)"
            }
        }
    }
}
