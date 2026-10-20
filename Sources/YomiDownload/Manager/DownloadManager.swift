import Foundation
import Network
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
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.yomi.downloader.network")
    private var hasWiFi = false
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var activeJobID: UUID?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.yomi.downloader.session")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let onWiFi = path.status == .satisfied
                && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            self.queueLock.lock()
            let becameAvailable = onWiFi && !self.hasWiFi
            self.hasWiFi = onWiFi
            self.queueLock.unlock()

            if becameAvailable {
                self.processNextJobIfNeeded()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    /// True while the queue is intentionally waiting for a Wi-Fi connection.
    public var isWaitingForWiFi: Bool {
        queueLock.lock()
        defer { queueLock.unlock() }
        return Self.wifiOnlyEnabled
            && !hasWiFi
            && queue.contains { $0.status == .queued }
    }

    /// Re-evaluates the queue, for example immediately after the user turns off Wi-Fi-only mode.
    public func processQueuedJobs() {
        processNextJobIfNeeded()
    }

    private static var wifiOnlyEnabled: Bool {
        (UserDefaults.standard.object(forKey: "yomi.download.wifiOnly") as? Bool) ?? true
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
        let task = activeTask
        activeTask = nil
        activeJobID = nil
        queueLock.unlock()
        task?.cancel()

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
        let isActive = activeJobID == jobId
        queue.removeAll { $0.id == jobId }
        let task = isActive ? activeTask : nil
        queueLock.unlock()

        task?.cancel()
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

        if Self.wifiOnlyEnabled && !hasWiFi {
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
        activeJobID = currentJob.id
        activeTask = Task {
            await executeDownload(job: currentJob)
        }
        queueLock.unlock()
    }

    private func executeDownload(job: DownloadJob) async {
        var stagingURL: URL?
        do {
            let pages = try await job.source.getPageList(chapter: job.chapter)
            let total = pages.count
            guard total > 0 else {
                throw YomiError.networkError("The source returned no pages for this chapter.")
            }

            guard let chId = job.chapter.id, let mId = job.manga.id,
                  let targetURL = getDownloadedCBZURL(chapterId: chId, mangaId: mId) else {
                throw YomiError.storageError("Invalid storage path")
            }

            let dirURL = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            // Write to a staging archive and publish only after the last page and ComicInfo.xml
            // are on disk. This avoids both a chapter-sized `[Data]` buffer and half-written
            // archives being treated as completed downloads.
            let partURL = targetURL.appendingPathExtension("part")
            stagingURL = partURL
            let writer = try CBZWriter(destinationURL: partURL, manga: job.manga, chapter: job.chapter)

            DownloadActivityController.shared.startActivity(
                mangaTitle: job.manga.title,
                chapterName: job.chapter.name,
                totalPages: total,
                remainingCount: queue.filter { $0.status == .queued }.count
            )

            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let data = try await job.source.getImageData(page: page)
                try Task.checkCancellation()
                try writer.appendImageData(data)

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

            try Task.checkCancellation()
            try writer.finish()
            try Task.checkCancellation()

            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.moveItem(at: partURL, to: targetURL)
            stagingURL = nil

            updateJobStatus(jobId: job.id, status: .completed(path: targetURL.path))
        } catch {
            if let stagingURL,
               FileManager.default.fileExists(atPath: stagingURL.path) {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            if !Task.isCancelled {
                updateJobStatus(jobId: job.id, status: .failed(error: error.localizedDescription))
            }
        }

        queueLock.lock()
        self.isProcessing = false
        if activeJobID == job.id {
            activeJobID = nil
            activeTask = nil
        }
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
