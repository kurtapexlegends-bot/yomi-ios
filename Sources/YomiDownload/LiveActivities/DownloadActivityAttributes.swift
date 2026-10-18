import Foundation
import ActivityKit

/// Attributes defining the Dynamic Island and Lock Screen Live Activity for active chapter downloads.
public struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentMangaTitle: String
        public var currentChapterName: String
        public var downloadedPages: Int
        public var totalPages: Int
        public var remainingJobsCount: Int
        public var progress: Double

        public init(
            currentMangaTitle: String,
            currentChapterName: String,
            downloadedPages: Int,
            totalPages: Int,
            remainingJobsCount: Int,
            progress: Double
        ) {
            self.currentMangaTitle = currentMangaTitle
            self.currentChapterName = currentChapterName
            self.downloadedPages = downloadedPages
            self.totalPages = totalPages
            self.remainingJobsCount = remainingJobsCount
            self.progress = progress
        }
    }

    public var queueId: String

    public init(queueId: String = UUID().uuidString) {
        self.queueId = queueId
    }
}

/// Controller managing the lifecycle of the download Live Activity.
public final class DownloadActivityController: @unchecked Sendable {
    public static let shared = DownloadActivityController()

    private var activeActivity: Activity<DownloadActivityAttributes>?

    private init() {}

    /// Starts a Dynamic Island Live Activity for a downloading chapter.
    public func startActivity(mangaTitle: String, chapterName: String, totalPages: Int, remainingCount: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = DownloadActivityAttributes()
        let initialContent = DownloadActivityAttributes.ContentState(
            currentMangaTitle: mangaTitle,
            currentChapterName: chapterName,
            downloadedPages: 0,
            totalPages: totalPages,
            remainingJobsCount: remainingCount,
            progress: 0.0
        )

        do {
            activeActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: nil)
            )
        } catch {
            print("[DownloadActivity] Failed to request Live Activity: \(error)")
        }
    }

    /// Updates the Live Activity with latest page progress.
    public func updateProgress(mangaTitle: String, chapterName: String, downloadedPages: Int, totalPages: Int, remainingCount: Int) {
        guard let activity = activeActivity else { return }

        let progress = totalPages > 0 ? Double(downloadedPages) / Double(totalPages) : 0.0
        let updatedContent = DownloadActivityAttributes.ContentState(
            currentMangaTitle: mangaTitle,
            currentChapterName: chapterName,
            downloadedPages: downloadedPages,
            totalPages: totalPages,
            remainingJobsCount: remainingCount,
            progress: progress
        )

        Task {
            await activity.update(.init(state: updatedContent, staleDate: nil))
        }
    }

    /// Dismisses the Live Activity once all chapter downloads are complete.
    public func endActivity() {
        guard let activity = activeActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activeActivity = nil
        }
    }
}
