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

/// A completed chapter archive discovered on disk.
public struct DownloadedChapterFile: Identifiable, Hashable, Sendable {
    public var id: String { "\(mangaId)_\(chapterId)" }
    public let mangaId: Int64
    public let chapterId: Int64
    public let fileURL: URL
    public let byteCount: Int64

    public init(mangaId: Int64, chapterId: Int64, fileURL: URL, byteCount: Int64) {
        self.mangaId = mangaId
        self.chapterId = chapterId
        self.fileURL = fileURL
        self.byteCount = byteCount
    }
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

    /// Lists every completed .cbz archive on disk, newest directory first.
    public func listDownloadedChapterFiles() -> [DownloadedChapterFile] {
        guard let root = downloadsRootURL() else { return [] }
        let fileManager = FileManager.default
        guard let mangaDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [DownloadedChapterFile] = []
        for mangaDir in mangaDirs {
            guard (try? mangaDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let mangaId = Int64(mangaDir.lastPathComponent) else { continue }
            let chapterFiles = (try? fileManager.contentsOfDirectory(
                at: mangaDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for file in chapterFiles where file.pathExtension.lowercased() == "cbz" {
                guard let chapterId = Int64(file.deletingPathExtension().lastPathComponent) else { continue }
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                files.append(DownloadedChapterFile(
                    mangaId: mangaId,
                    chapterId: chapterId,
                    fileURL: file,
                    byteCount: Int64(size)
                ))
            }
        }
        return files.sorted { $0.fileURL.path < $1.fileURL.path }
    }

    /// Number of downloaded chapters per manga, used by library filters and badges.
    public func downloadedChapterCounts() -> [Int64: Int] {
        listDownloadedChapterFiles().reduce(into: [Int64: Int]()) { counts, file in
            counts[file.mangaId, default: 0] += 1
        }
    }

    public func downloadedChapterIDs() -> Set<Int64> {
        Set(listDownloadedChapterFiles().map(\.chapterId))
    }

    public func totalDownloadedBytes() -> Int64 {
        listDownloadedChapterFiles().reduce(0) { $0 + $1.byteCount }
    }

    /// Deletes every downloaded archive. Active queue jobs are cancelled first.
    public func deleteAllDownloadedChapters() throws {
        queueLock.lock()
        queue.removeAll()
        queueLock.unlock()

        guard let root = downloadsRootURL(), FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    private func downloadsRootURL() -> URL? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent("Yomi/downloads", isDirectory: true)
        } catch {
            return nil
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

    /// Removes completed and failed jobs while keeping active work untouched.
    public func clearFinishedJobs() {
        queueLock.lock()
        queue.removeAll { job in
            switch job.status {
            case .completed, .failed:
                return true
            case .queued, .downloading, .paused:
                return false
            }
        }
        queueLock.unlock()
    }

    /// Requeues a failed download. Existing partial archives are overwritten on completion.
    public func retry(jobId: UUID) {
        queueLock.lock()
        if let index = queue.firstIndex(where: { $0.id == jobId }) {
            queue[index].status = .queued
        }
        queueLock.unlock()
        processNextJobIfNeeded()
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
