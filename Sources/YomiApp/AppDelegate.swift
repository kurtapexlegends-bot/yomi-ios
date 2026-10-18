import Foundation
import UserNotifications
import YomiCore
import YomiDownload
import YomiSync

#if canImport(UIKit)
import UIKit

public final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register Background Tasks
        LibraryUpdateScheduler.shared.registerBackgroundTask()

        // Start iCloud sync listener
        CloudSyncCoordinator.shared.startObserving()

        // Request local notification permissions for chapter releases
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("[AppDelegate] Notification authorization error: \(error)")
            }
        }

        return true
    }

    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "com.yomi.downloader.session" {
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Present banner and sound even if app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
#else
public final class AppDelegate: NSObject {
    public override init() { super.init() }
}
#endif
