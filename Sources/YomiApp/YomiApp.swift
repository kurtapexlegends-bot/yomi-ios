import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiUI
import YomiSync

@main
public struct YomiApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @Environment(\.scenePhase) private var scenePhase

    private let biometricManager = BiometricSecurityManager.shared
    private let privacyManager = PrivacyManager.shared
    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()

    public init() {
        // Initialize Core Database on startup
        _ = DatabaseManager.shared
    }

    public var body: some Scene {
        WindowGroup {
            AppRootView()
                .preferredColorScheme(.dark) // Pure OLED True Black experience
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            privacyManager.deactivatePrivacyShield()
            biometricManager.handleAppWillEnterForeground()
        case .inactive:
            privacyManager.activatePrivacyShield()
        case .background:
            privacyManager.activatePrivacyShield()
            biometricManager.handleAppDidEnterBackground()
            LibraryUpdateScheduler.shared.scheduleNextLibraryRefresh()
        @unknown default:
            break
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.isFileURL {
            // Local CBZ/CBR/ZIP comic import from Files app or AirDrop
            Task {
                do {
                    let (manga, chapter) = try LocalComicImporter.importArchive(from: url)
                    let savedManga = try await mangaRepo.upsert(manga)
                    if let mangaId = savedManga.id {
                        var ch = chapter
                        ch.mangaId = mangaId
                        _ = try await chapterRepo.syncChapters([ch], forMangaId: mangaId)
                    }
                } catch {
                    print("[YomiApp] Failed to import local comic archive: \(error)")
                }
            }
        } else if url.scheme == "yomi" {
            // Handle OAuth callbacks (e.g. AniList yomi://oauth#access_token=...)
            if let fragment = url.fragment, fragment.contains("access_token=") {
                let params = fragment.components(separatedBy: "&")
                for param in params {
                    let pair = param.components(separatedBy: "=")
                    if pair.count == 2 && pair[0] == "access_token" {
                        AniListClient.shared.accessToken = pair[1]
                        break
                    }
                }
            }
        }
    }
}
