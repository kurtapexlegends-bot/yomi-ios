import SwiftUI
import YomiCore
import YomiReader
import YomiSync

public struct SettingsView: View {
    @State private var biometricManager = BiometricSecurityManager.shared
    @State private var privacyManager = PrivacyManager.shared
    @State private var defaultViewer: MangaViewer = .defaultViewer
    @State private var isAutocropEnabled: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isShowingAniListAlert: Bool = false
    @State private var aniListTokenInput: String = ""
    @State private var statusMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - Reading Preferences
                Section("Reader Defaults") {
                    Picker("Default Reading Mode", selection: $defaultViewer) {
                        ForEach(MangaViewer.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("Autocrop Borders by Default", isOn: $isAutocropEnabled)
                }

                // MARK: - Privacy & Security
                Section("Security & Privacy") {
                    Toggle("Face ID / Touch ID App Lock", isOn: $biometricManager.isAppLockEnabled)
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

                    Toggle("Incognito Mode", isOn: Binding(
                        get: { privacyManager.isIncognitoMode },
                        set: { _ in privacyManager.toggleIncognito() }
                    ))

                    Toggle("App Switcher Privacy Blur", isOn: $privacyManager.isSnapshotProtectionEnabled)
                }

                // MARK: - Backup & Sync
                Section("Backup & Migration") {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Restore Tachiyomi / Mihon Backup (.tachibk)", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        exportTachiyomiBackup()
                    } label: {
                        Label("Export Yomi Backup (.tachibk)", systemImage: "square.and.arrow.up")
                    }
                }

                // MARK: - External Trackers
                Section("External Tracking") {
                    HStack {
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
                        }
                    }
                }

                // MARK: - Cache & Storage
                Section("Storage & Performance") {
                    Button("Purge Image Memory Cache") {
                        ImageDownsampler.shared.purgeMemory()
                        statusMessage = "Image cache purged."
                    }
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    HStack {
                        Text("Bundle Identifier")
                        Spacer()
                        Text("com.yomiapp.reader")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    HStack {
                        Text("Architecture")
                        Spacer()
                        Text("Native Swift 5.10 / SwiftUI")
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
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
        }
    }

    private func handleBackupImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            Task {
                do {
                    let counts = try await TachibkManager.shared.restoreBackup(from: fileURL)
                    statusMessage = "Restored \(counts.restoredMangas) manga and \(counts.restoredChapters) chapters."
                } catch {
                    statusMessage = "Restore failed: \(error.localizedDescription)"
                }
            }
        case .failure(let err):
            statusMessage = "File import error: \(err.localizedDescription)"
        }
    }

    private func exportTachiyomiBackup() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let exportURL = tempDir.appendingPathComponent("yomi_\(Int(Date().timeIntervalSince1970)).tachibk")
                try await TachibkManager.shared.exportBackup(to: exportURL)
                statusMessage = "Backup saved to \(exportURL.lastPathComponent)"
            } catch {
                statusMessage = "Backup failed: \(error.localizedDescription)"
            }
        }
    }
}
