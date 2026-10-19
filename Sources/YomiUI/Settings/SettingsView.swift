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
    @State private var defaultViewer: MangaViewer = .defaultViewer
    @State private var isAutocropEnabled: Bool = false
    @State private var isInvertColorsEnabled: Bool = false
    @State private var downloadOnlyOnWifi: Bool = true
    @State private var autoDownloadNextChapters: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingAniListAlert: Bool = false
    @State private var aniListTokenInput: String = ""
    @State private var statusToast: String?
    @State private var isShowingClearCacheAlert: Bool = false
    @State private var isShowingRebuildFTSAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - App Header Banner
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(YomiTheme.accent)
                            .frame(width: 56, height: 56)
                            .background(YomiTheme.accent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yomi")
                                .font(.title3.bold())
                                .foregroundStyle(YomiTheme.textPrimary)
                            Text("Zero-OOM Native Comic Reader")
                                .font(.caption)
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Appearance & Theme
                Section {
                    HStack {
                        SettingsIconBadge(icon: "moon.fill", color: .purple)
                        Text("Theme")
                        Spacer()
                        Text("Pure Black OLED")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }

                    HStack {
                        SettingsIconBadge(icon: "paintpalette.fill", color: .indigo)
                        Text("Accent Color")
                        Spacer()
                        Circle()
                            .fill(YomiTheme.accent)
                            .frame(width: 18, height: 18)
                    }
                } header: {
                    Text("Appearance")
                }

                // MARK: - Reader Preferences
                Section {
                    HStack {
                        SettingsIconBadge(icon: "book.pages.fill", color: .blue)
                        Picker("Default Reading Mode", selection: $defaultViewer) {
                            ForEach(MangaViewer.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }

                    Toggle(isOn: $isAutocropEnabled) {
                        HStack {
                            SettingsIconBadge(icon: "crop", color: .cyan)
                            Text("Autocrop Whitespace Margins")
                        }
                    }

                    Toggle(isOn: $isInvertColorsEnabled) {
                        HStack {
                            SettingsIconBadge(icon: "circle.righthalf.filled", color: .teal)
                            Text("Invert Colors (OLED Saver)")
                        }
                    }
                } header: {
                    Text("Reader Engine")
                } footer: {
                    Text("Autocrop removes excessive borders from comic scans to maximize screen space.")
                }

                // MARK: - Sources & Extensions
                Section {
                    NavigationLink {
                        BrowseView()
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "globe", color: .orange)
                            Text("Sources & Extensions")
                            Spacer()
                            Text("\(ExtensionManager.shared.installedSources.count) active")
                                .font(.caption)
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }

                    HStack {
                        SettingsIconBadge(icon: "network", color: .blue)
                        Text("Default User-Agent")
                        Spacer()
                        Text("iOS Safari Native")
                            .font(.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                } header: {
                    Text("Sources")
                }

                // MARK: - Downloads & Storage
                Section {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "arrow.down.circle.fill", color: .green)
                            Text("Downloads Manager")
                        }
                    }

                    Toggle(isOn: $downloadOnlyOnWifi) {
                        HStack {
                            SettingsIconBadge(icon: "wifi", color: .green)
                            Text("Download Only on Wi-Fi")
                        }
                    }

                    Toggle(isOn: $autoDownloadNextChapters) {
                        HStack {
                            SettingsIconBadge(icon: "arrow.down.to.line.compact", color: .mint)
                            Text("Auto-Download Next Chapter")
                        }
                    }

                    Button {
                        isShowingClearCacheAlert = true
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "trash.fill", color: .red)
                            Text("Purge Image Memory Cache")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("150 MB Limit")
                                .font(.caption)
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }
                } header: {
                    Text("Downloads & Storage")
                }

                // MARK: - External Trackers
                Section {
                    HStack {
                        SettingsIconBadge(icon: "arrow.triangle.2.circlepath", color: .blue)
                        Text("AniList")
                        Spacer()
                        if AniListClient.shared.isLoggedIn {
                            Text("Connected")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Button("Connect") {
                                isShowingAniListAlert = true
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(YomiTheme.accent)
                        }
                    }
                } header: {
                    Text("Tracking & Sync")
                }

                // MARK: - Backup & Migration
                Section {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "arrow.counterclockwise", color: .indigo)
                            Text("Restore Tachiyomi / Mihon Backup (.tachibk)")
                                .foregroundStyle(.primary)
                        }
                    }

                    Button {
                        exportTachiyomiBackup()
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "square.and.arrow.up", color: .purple)
                            Text("Export Yomi Backup (.tachibk)")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Backup & Migration")
                }

                // MARK: - Privacy & Security
                Section {
                    Toggle(isOn: $biometricManager.isAppLockEnabled) {
                        HStack {
                            SettingsIconBadge(icon: "lock.shield.fill", color: .red)
                            Text("Face ID / Touch ID App Lock")
                        }
                    }
                    .onChange(of: biometricManager.isAppLockEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await biometricManager.requestUnlock() }
                        }
                    }

                    if biometricManager.isAppLockEnabled {
                        Picker("Require Unlock", selection: $biometricManager.gracePeriod) {
                            ForEach(LockGracePeriod.allCases, id: \.self) { period in
                                Text(period.title).tag(period)
                            }
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { privacyManager.isIncognitoMode },
                        set: { _ in privacyManager.toggleIncognito() }
                    )) {
                        HStack {
                            SettingsIconBadge(icon: "eye.slash.fill", color: .purple)
                            Text("Incognito Mode")
                        }
                    }

                    Toggle(isOn: $privacyManager.isSnapshotProtectionEnabled) {
                        HStack {
                            SettingsIconBadge(icon: "square.dashed", color: .gray)
                            Text("App Switcher Privacy Blur")
                        }
                    }
                } header: {
                    Text("Security & Privacy")
                }

                // MARK: - Advanced Diagnostics
                Section {
                    Button {
                        isShowingRebuildFTSAlert = true
                    } label: {
                        HStack {
                            SettingsIconBadge(icon: "magnifyingglass.circle.fill", color: .yellow)
                            Text("Rebuild Full-Text Search Index (FTS5)")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Advanced & Database")
                }

                // MARK: - About
                Section {
                    HStack {
                        SettingsIconBadge(icon: "info.circle.fill", color: .gray)
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 2)")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    HStack {
                        SettingsIconBadge(icon: "shippingbox.fill", color: .gray)
                        Text("Bundle Identifier")
                        Spacer()
                        Text("com.yomiapp.reader")
                            .font(.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    HStack {
                        SettingsIconBadge(icon: "cpu.fill", color: .gray)
                        Text("Architecture")
                        Spacer()
                        Text("Native Swift 5.10 / GRDB / CATiledLayer")
                            .font(.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result: result)
            }
            .alert("Connect AniList", isPresented: $isShowingAniListAlert) {
                TextField("Enter AniList OAuth Token", text: $aniListTokenInput)
                Button("Save") {
                    AniListClient.shared.accessToken = aniListTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    aniListTokenInput = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paste your personal access token generated from your AniList account developer settings.")
            }
            .alert("Purge Image Cache", isPresented: $isShowingClearCacheAlert) {
                Button("Purge", role: .destructive) {
                    ImageDownsampler.shared.purgeMemory()
                    statusToast = "Image cache purged successfully."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will instantly clear decoded in-memory images, freeing system memory.")
            }
            .alert("Rebuild Search Index", isPresented: $isShowingRebuildFTSAlert) {
                Button("Rebuild", role: .destructive) {
                    rebuildFTSIndex()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Re-indexes library mangas and authors in SQLite for instantaneous search results.")
            }
            .overlay(alignment: .bottom) {
                if let toast = statusToast {
                    Text(toast)
                        .font(.caption.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .foregroundStyle(.white)
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
        case .failure(let err):
            statusToast = "File import error: \(err.localizedDescription)"
        }
    }

    private func exportTachiyomiBackup() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let exportURL = tempDir.appendingPathComponent("yomi_\(Int(Date().timeIntervalSince1970)).tachibk")
                try await TachibkManager.shared.exportBackup(to: exportURL)
                statusToast = "Backup exported to \(exportURL.lastPathComponent)"
            } catch {
                statusToast = "Backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func rebuildFTSIndex() {
        Task {
            do {
                try await MangaRepository().rebuildFTSIndex()
                statusToast = "FTS5 search index successfully rebuilt."
            } catch {
                statusToast = "Rebuild failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Settings Icon Badge Component

struct SettingsIconBadge: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
