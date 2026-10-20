import SwiftUI
import YomiCore
import YomiReader
import YomiSync
import YomiDownload
import YomiExtensions
import YomiDatabase

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
        ZStack {
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    appearanceSection
                    readerSection
                    librarySection
                    sourcesSection
                    downloadsSection
                    trackingSection
                    backupSection
                    securitySection
                    advancedSection
                    aboutSection
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 36)
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
            Text("Create a personal access token in your AniList developer settings, then paste it here.")
        }
        .alert("Purge Image Cache", isPresented: $isShowingClearCacheAlert) {
            Button("Purge", role: .destructive) {
                ImageDownsampler.shared.purgeMemory()
                statusToast = "Decoded image memory cleared."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears decoded images from memory. Downloads and library data are untouched.")
        }
        .alert("Rebuild Search Index", isPresented: $isShowingRebuildFTSAlert) {
            Button("Rebuild", role: .destructive) { rebuildFTSIndex() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Re-indexes library titles and authors for instant local search.")
        }
        .alert("Reset Cloudflare Sessions", isPresented: $isShowingResetWebDataAlert) {
            Button("Reset", role: .destructive) {
                CloudflareSolver.shared.resetVerification()
                statusToast = "Cloudflare sessions will be verified again when needed."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this if a source keeps asking for verification after you have completed it.")
        }
        .overlay(alignment: .bottom) {
            if let toast = statusToast {
                Text(toast)
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .overlay(Capsule().stroke(YomiTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { statusToast = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        YomiCard(padding: 18) {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(YomiTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Yomi")
                        .font(YomiFont.sectionTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text("Native reading, tuned for OLED")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Spacer()
                Text("1.0.0")
                    .font(YomiFont.number)
                    .foregroundStyle(YomiTheme.textTertiary)
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        settingsGroup("Appearance") {
            infoRow(icon: "moon.fill", tint: YomiTheme.accentStrong, title: "Theme", value: "OLED Black")
            divider
            HStack(spacing: 12) {
                settingsIcon("paintpalette.fill", tint: YomiTheme.accentStrong)
                Text("Accent")
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                Spacer()
                Circle().fill(YomiTheme.accent).frame(width: 18, height: 18)
            }
            .padding(.vertical, 11)
            divider
            Picker(selection: $libraryLayout) {
                Text("Grid").tag("grid")
                Text("List").tag("list")
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("square.grid.2x2.fill", tint: YomiTheme.unreadBadge)
                    Text("Library layout")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .tint(YomiTheme.accentStrong)
            .padding(.vertical, 2)
        }
    }

    private var readerSection: some View {
        settingsGroup("Reader Engine") {
            Picker(selection: viewerBinding) {
                ForEach(MangaViewer.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("book.pages.fill", tint: YomiTheme.unreadBadge)
                    Text("Default reading mode")
                        .font(YomiFont.body.weight(.semibold))
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
                    settingsIcon("hand.tap.fill", tint: YomiTheme.warning)
                    Text("Tap navigation")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                }
            }
            .pickerStyle(.menu)
            .tint(YomiTheme.accentStrong)
            .padding(.vertical, 2)
            divider
            toggleRow(icon: "crop", tint: YomiTheme.success, title: "Autocrop borders", isOn: $isAutocropEnabled)
            divider
            toggleRow(icon: "circle.righthalf.filled", tint: YomiTheme.accentStrong, title: "Invert colors", isOn: $isInvertColorsEnabled)
            divider
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    settingsIcon("sun.max.fill", tint: YomiTheme.warning)
                    Text("Reader brightness")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Text("\(Int(readerBrightness * 100))%")
                        .font(YomiFont.number)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Slider(value: $readerBrightness, in: 0.1...1.0)
                    .tint(YomiTheme.accent)
                    .padding(.leading, 42)
            }
            .padding(.vertical, 8)
        }
    }

    private var librarySection: some View {
        settingsGroup("Library") {
            NavigationLink {
                CategoryManagerView()
            } label: {
                navigationRow(icon: "folder.fill", tint: YomiTheme.warning, title: "Categories", value: "Organize shelves")
            }
            divider
            NavigationLink {
                StatisticsView()
            } label: {
                navigationRow(icon: "chart.bar.fill", tint: YomiTheme.unreadBadge, title: "Reading statistics", value: "Local only")
            }
        }
    }

    private var sourcesSection: some View {
        settingsGroup("Sources") {
            NavigationLink {
                ExtensionStoreView()
            } label: {
                navigationRow(
                    icon: "puzzlepiece.extension.fill",
                    tint: YomiTheme.accentStrong,
                    title: "Extension store",
                    value: "\(extensionManager.installedSources.count) installed"
                )
            }
            divider
            infoRow(icon: "network", tint: YomiTheme.unreadBadge, title: "User agent", value: "Safari iOS")
            divider
            Button {
                isShowingResetWebDataAlert = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("arrow.counterclockwise", tint: YomiTheme.warning)
                    Text("Reset Cloudflare verification")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }

    private var downloadsSection: some View {
        settingsGroup("Downloads & Storage") {
            NavigationLink {
                DownloadsView()
            } label: {
                navigationRow(
                    icon: "arrow.down.circle.fill",
                    tint: YomiTheme.success,
                    title: "Downloaded chapters",
                    value: "\(downloadedCount) · \(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))"
                )
            }
            divider
            toggleRow(icon: "wifi", tint: YomiTheme.success, title: "Wi-Fi only", isOn: $downloadOnlyOnWifi)
            divider
            toggleRow(icon: "arrow.down.to.line.compact", tint: YomiTheme.unreadBadge, title: "Auto-download next chapter", isOn: $autoDownloadNextChapters)
            divider
            Button {
                isShowingClearCacheAlert = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("memorychip", tint: YomiTheme.danger)
                    Text("Purge image memory cache")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Text("150 MB cap")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }

    private var trackingSection: some View {
        settingsGroup("Tracking") {
            HStack(spacing: 12) {
                settingsIcon("arrow.triangle.2.circlepath", tint: YomiTheme.unreadBadge)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AniList")
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(AniListClient.shared.isLoggedIn ? "Connected and syncing" : "Not connected")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Spacer()
                if AniListClient.shared.isLoggedIn {
                    Button("Disconnect") {
                        AniListClient.shared.accessToken = nil
                        statusToast = "AniList disconnected."
                    }
                    .font(YomiFont.caption.weight(.bold))
                    .foregroundStyle(YomiTheme.danger)
                } else {
                    Button("Connect") { isShowingAniListAlert = true }
                        .font(YomiFont.caption.weight(.bold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .padding(.vertical, 11)
        }
    }

    private var backupSection: some View {
        settingsGroup("Backup & Migration") {
            Button {
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("arrow.counterclockwise", tint: YomiTheme.accentStrong)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore Mihon backup")
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("Import .tachibk library data")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YomiTheme.textTertiary)
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            divider
            Button {
                exportTachiyomiBackup()
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("square.and.arrow.up", tint: YomiTheme.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Yomi backup")
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("Create a .tachibk archive")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            if let exportedBackupURL {
                divider
                ShareLink(item: exportedBackupURL) {
                    HStack(spacing: 12) {
                        settingsIcon("doc.badge.arrow.up", tint: YomiTheme.success)
                        Text("Share latest backup")
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private var securitySection: some View {
        settingsGroup("Security & Privacy") {
            toggleRow(icon: "lock.shield.fill", tint: YomiTheme.danger, title: "Biometric app lock", isOn: $biometricManager.isAppLockEnabled)
            if biometricManager.isAppLockEnabled {
                divider
                Picker(selection: $biometricManager.gracePeriod) {
                    ForEach(LockGracePeriod.allCases, id: \.self) { period in
                        Text(period.title).tag(period)
                    }
                } label: {
                    HStack(spacing: 12) {
                        settingsIcon("timer", tint: YomiTheme.warning)
                        Text("Require unlock")
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                    }
                }
                .pickerStyle(.menu)
                .tint(YomiTheme.accentStrong)
                .padding(.vertical, 2)
            }
            divider
            toggleRow(
                icon: "eye.slash.fill",
                tint: YomiTheme.accentStrong,
                title: "Incognito mode",
                isOn: Binding(
                    get: { privacyManager.isIncognitoMode },
                    set: { _ in privacyManager.toggleIncognito() }
                )
            )
            divider
            toggleRow(icon: "square.dashed", tint: YomiTheme.textSecondary, title: "App switcher privacy blur", isOn: $privacyManager.isSnapshotProtectionEnabled)
        }
    }

    private var advancedSection: some View {
        settingsGroup("Advanced") {
            Button {
                isShowingRebuildFTSAlert = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("magnifyingglass.circle.fill", tint: YomiTheme.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rebuild search index")
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("FTS5 · local SQLite")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        settingsGroup("About") {
            NavigationLink {
                AboutView()
            } label: {
                navigationRow(icon: "info.circle.fill", tint: YomiTheme.textSecondary, title: "About Yomi", value: "1.0.0")
            }
        }
    }

    // MARK: - Building blocks

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(YomiFont.micro)
                .tracking(1.5)
                .foregroundStyle(YomiTheme.textTertiary)
                .padding(.leading, 3)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    private func settingsIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(YomiTheme.border)
    }

    private func infoRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, tint: tint)
            Text(title)
                .font(YomiFont.body.weight(.semibold))
                .foregroundStyle(YomiTheme.textPrimary)
            Spacer()
            Text(value)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
        }
        .padding(.vertical, 11)
    }

    private func toggleRow(icon: String, tint: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, tint: tint)
            Toggle(title, isOn: isOn)
                .font(YomiFont.body.weight(.semibold))
                .foregroundStyle(YomiTheme.textPrimary)
                .tint(YomiTheme.accent)
        }
        .padding(.vertical, 5)
    }

    private func navigationRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, tint: tint)
            Text(title)
                .font(YomiFont.body.weight(.semibold))
                .foregroundStyle(YomiTheme.textPrimary)
            Spacer()
            Text(value)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .padding(.vertical, 11)
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
                    statusToast = "Restored \(counts.restoredMangas) manga and \(counts.restoredChapters) chapters."
                } catch {
                    statusToast = "Restore failed: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            statusToast = "File import error: \(error.localizedDescription)"
        }
    }

    private func exportTachiyomiBackup() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let exportURL = tempDir.appendingPathComponent("yomi_\(Int(Date().timeIntervalSince1970)).tachibk")
                try await TachibkManager.shared.exportBackup(to: exportURL)
                exportedBackupURL = exportURL
                statusToast = "Backup ready to share."
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
