import Foundation
import Observation
import YomiCore

public enum DownloadStatus: Sendable, Equatable {
    case queued
    case downloading(progress: Float, current: Int, total: Int)
    case completed(path: String)
    case failed(error: String)
    case paused
}

public struct DownloadJob: Identifiable, Sendable {
    public let id: UUID
    public let manga: Manga
    public let chapter: Chapter
    public let source: any SourceProtocol
    public var status: DownloadStatus

    public init(
        id: UUID = UUID(),
        manga: Manga,
        chapter: Chapter,
        source: any SourceProtocol,
        status: DownloadStatus = .queued
    ) {
        self.id = id
        self.manga = manga
        self.chapter = chapter
        self.source = source
        self.status = status
    }
}

/// Central manager orchestrating background URLSession downloads and .cbz archive generation.
@Observable
public final class DownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = DownloadManager()

    public private(set) var queue: [DownloadJob] = []
    public private(set) var isProcessing: Bool = false
    public var backgroundCompletionHandler: (() -> Void)?

    private var backgroundSession: URLSession!
    private let queueLock = NSLock()

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.yomi.downloader.session")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Enqueues chapters for background download.
    public func enqueue(manga: Manga, chapters: [Chapter], source: any SourceProtocol) {
        queueLock.lock()
        for chapter in chapters {
            guard let chId = chapter.id, let mId = manga.id, !isChapterDownloaded(chapterId: chId, mangaId: mId) else {
                continue
            }
            if !queue.contains(where: { $0.chapter.id == chapter.id }) {
                queue.append(DownloadJob(manga: manga, chapter: chapter, source: source, status: .queued))
            }
        }
        queueLock.unlock()

        processNextJobIfNeeded()
    }

    /// Checks if a chapter file exists on local storage.
    public func isChapterDownloaded(chapterId: Int64, mangaId: Int64) -> Bool {
        guard let url = getDownloadedCBZURL(chapterId: chapterId, mangaId: mangaId) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Returns the file URL of the downloaded .cbz archive.
    public func getDownloadedCBZURL(chapterId: Int64, mangaId: Int64) -> URL? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent("Yomi/downloads/\(mangaId)/\(chapterId).cbz")
        } catch {
            return nil
        }
    }

    /// Deletes a downloaded chapter archive from disk.
    public func deleteDownloadedChapter(chapterId: Int64, mangaId: Int64) throws {
        if let url = getDownloadedCBZURL(chapterId: chapterId, mangaId: mangaId),
           FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Pauses an active or queued download job.
    public func pause(jobId: UUID) {
        queueLock.lock()
        defer { queueLock.unlock() }
        if let idx = queue.firstIndex(where: { $0.id == jobId }) {
            queue[idx].status = .paused
        }
    }

    /// Cancels and removes a job from the queue.
    public func cancel(jobId: UUID) {
        queueLock.lock()
        defer { queueLock.unlock() }
        queue.removeAll { $0.id == jobId }
    }

    // MARK: - Queue Processing

    private func processNextJobIfNeeded() {
        queueLock.lock()
        guard !isProcessing else {
            queueLock.unlock()
            return
        }

        guard let nextIndex = queue.firstIndex(where: { $0.status == .queued }) else {
            queueLock.unlock()
            DownloadActivityController.shared.endActivity()
            return
        }

        self.isProcessing = true
        let currentJob = queue[nextIndex]
        queue[nextIndex].status = .downloading(progress: 0, current: 0, total: 0)
        queueLock.unlock()

        Task {
            await executeDownload(job: currentJob)
        }
    }

    private func executeDownload(job: DownloadJob) async {
        do {
            let pages = try await job.source.getPageList(chapter: job.chapter)
            let total = pages.count

            DownloadActivityController.shared.startActivity(
                mangaTitle: job.manga.title,
                chapterName: job.chapter.name,
                totalPages: total,
                remainingCount: queue.filter { $0.status == .queued }.count
            )

            var pageDataList: [Data] = []
            for (index, page) in pages.enumerated() {
                let data = try await job.source.getImageData(page: page)
                pageDataList.append(data)

                let progress = Float(index + 1) / Float(total)
                updateJobStatus(jobId: job.id, status: .downloading(progress: progress, current: index + 1, total: total))

                DownloadActivityController.shared.updateProgress(
                    mangaTitle: job.manga.title,
                    chapterName: job.chapter.name,
                    downloadedPages: index + 1,
                    totalPages: total,
                    remainingCount: queue.filter { $0.status == .queued }.count
                )
            }

            // Write CBZ
            guard let chId = job.chapter.id, let mId = job.manga.id,
                  let targetURL = getDownloadedCBZURL(chapterId: chId, mangaId: mId) else {
                throw YomiError.storageError("Invalid storage path")
            }

            let dirURL = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try CBZArchiver.createCBZ(at: targetURL, manga: job.manga, chapter: job.chapter, pageDataList: pageDataList)

            updateJobStatus(jobId: job.id, status: .completed(path: targetURL.path))
        } catch {
            updateJobStatus(jobId: job.id, status: .failed(error: error.localizedDescription))
        }

        queueLock.lock()
        self.isProcessing = false
        queueLock.unlock()

        processNextJobIfNeeded()
    }

    private func updateJobStatus(jobId: UUID, status: DownloadStatus) {
        queueLock.lock()
        defer { queueLock.unlock() }
        if let idx = queue.firstIndex(where: { $0.id == jobId }) {
            queue[idx].status = status
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled through synchronous page fetches or background task callbacks
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
