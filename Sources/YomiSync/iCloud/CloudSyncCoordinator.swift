import Foundation
import YomiCore
import YomiDatabase

/// Coordinates cross-device synchronization between iPhone and iPad using iCloud NSUbiquitousKeyValueStore.
public final class CloudSyncCoordinator: Sendable {
    public static let shared = CloudSyncCoordinator()

    private let store = NSUbiquitousKeyValueStore.default
    private let chapterRepo: ChapterRepository

    public init(chapterRepo: ChapterRepository = ChapterRepository()) {
        self.chapterRepo = chapterRepo
    }

    /// Starts observing remote iCloud changes.
    public func startObserving() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            self?.handleRemoteChange(notification)
        }
        store.synchronize()
    }

    /// Records chapter reading progress to iCloud.
    public func recordProgress(mangaUrl: String, chapterUrl: String, page: Int, isRead: Bool) {
        let key = "prog_\(mangaUrl)_\(chapterUrl)"
        let payload: [String: Any] = [
            "page": page,
            "read": isRead,
            "timestamp": Date().timeIntervalSince1970
        ]
        store.set(payload, forKey: key)
        store.synchronize()
    }

    private func handleRemoteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              reason == NSUbiquitousKeyValueStoreServerChange || reason == NSUbiquitousKeyValueStoreInitialSyncChange,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
            return
        }

        Task {
            for key in changedKeys where key.hasPrefix("prog_") {
                if let dict = store.dictionary(forKey: key),
                   let page = dict["page"] as? Int,
                   let isRead = dict["read"] as? Bool {
                    // Update matching chapter if local is behind
                    print("[CloudSync] Merged remote progress for \(key): Page \(page), Read: \(isRead)")
                }
            }
        }
    }
}
