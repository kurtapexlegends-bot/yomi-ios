import Foundation
#if os(iOS)
import BackgroundTasks
#endif
import UserNotifications
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

/// Orchestrates periodic background library updates and chapter release notifications.
public final class LibraryUpdateScheduler: @unchecked Sendable {
    public static let shared = LibraryUpdateScheduler()
    public static let taskIdentifier = "com.yomiapp.reader.libraryupdate"

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let extensionManager = ExtensionManager.shared
    private let downloadManager = DownloadManager.shared

    private init() {}

    /// Registers the background task identifier with iOS BGTaskScheduler.
    public func registerBackgroundTask() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: appRefreshTask)
        }
        #endif
    }

    /// Schedules the next background library refresh (typically after 6 to 12 hours).
    public func scheduleNextLibraryRefresh() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600) // 6 hours

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[LibraryUpdateScheduler] Failed to submit background refresh: \(error)")
        }
        #endif
    }

    #if os(iOS)
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextLibraryRefresh()

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        Task {
            let success = await executeLibraryUpdate()
            task.setTaskCompleted(success: success)
        }
    }
    #endif

    private func executeLibraryUpdate() async -> Bool {
        do {
            let libraryMangas = try await mangaRepo.getLibraryMangas()
            var newChaptersFound = 0

            for manga in libraryMangas {
                guard let mangaId = manga.id,
                      let src = extensionManager.getSource(id: manga.sourceId) else { continue }

                // Fetch existing chapters
                let existingChapters = try await chapterRepo.getChapters(forMangaId: mangaId)
                let existingUrls = Set(existingChapters.map { $0.url })

                // Fetch latest chapters from remote source
                let freshChapters = try await src.getChapterList(manga: manga)
                let newlyDiscovered = freshChapters.filter { !existingUrls.contains($0.url) }

                if !newlyDiscovered.isEmpty {
                    _ = try await chapterRepo.syncChapters(freshChapters, forMangaId: mangaId)
                    newChaptersFound += newlyDiscovered.count

                    // Send local notification
                    if let newest = newlyDiscovered.first {
                        sendNewChapterNotification(mangaTitle: manga.title, chapterTitle: newest.displayTitle)
                    }

                    // Auto-download new chapters if enabled
                    let autoDownload = UserDefaults.standard.bool(forKey: "yomi_auto_download_new_chapters")
                    if autoDownload {
                        downloadManager.enqueue(manga: manga, chapters: newlyDiscovered, source: src)
                    }
                }
            }

            return true
        } catch {
            print("[LibraryUpdateScheduler] Error updating library: \(error)")
            return false
        }
    }

    private func sendNewChapterNotification(mangaTitle: String, chapterTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Chapter: \(mangaTitle)"
        content.body = chapterTitle
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )

        UNUserNotificationCenter.current().add(request)
    }
}
