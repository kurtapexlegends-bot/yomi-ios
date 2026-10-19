import Foundation
import WebKit
import Observation
import YomiCore

/// Coordinates interactive and automated Cloudflare challenge resolution and cookie synchronization.
@Observable
public final class CloudflareSolver: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = CloudflareSolver()

    /// State indicating whether an interactive captcha solver modal sheet needs to be shown.
    public var isPresentingSolverSheet: Bool = false
    public var activeChallengeUrl: URL?
    public var activeWebView: WKWebView?

    private var completionHandler: ((Bool) -> Void)?
    private var pollTimer: Task<Void, Never>?

    private override init() {
        super.init()
    }

    /// Resolves a Cloudflare anti-bot challenge by presenting the interactive solver sheet.
    @MainActor
    public func resolveChallenge(for url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.cancelCurrentSession()
            self.activeChallengeUrl = url
            self.completionHandler = { [weak self] success in
                guard let self = self else { return }
                self.pollTimer?.cancel()
                self.pollTimer = nil
                self.isPresentingSolverSheet = false
                self.activeWebView = nil
                continuation.resume(returning: success)
            }

            self.isPresentingSolverSheet = true

            // Periodically inspect cookies in background while sheet is presented
            self.pollTimer = Task { @MainActor [weak self] in
                for _ in 0..<60 { // Poll up to 90 seconds
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self = self, self.isPresentingSolverSheet, let activeWv = self.activeWebView else { continue }
                    self.inspectChallengeStatus(in: activeWv)
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inspectChallengeStatus(in: webView)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Keep interactive web view alive so user can refresh or solve Turnstile
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // If provisional navigation fails (e.g. transient network or Cloudflare HTTP 403 status), keep sheet active
    }

    private func inspectChallengeStatus(in webView: WKWebView) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let hasClearance = cookies.contains { $0.name == "cf_clearance" || $0.name == "__cf_bm" }
            if hasClearance {
                self.syncCookiesAndComplete(cookies: cookies, success: true)
            }
        }
    }

    private func syncCookiesAndComplete(cookies: [HTTPCookie], success: Bool) {
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollTimer?.cancel()
            self.pollTimer = nil
            self.isPresentingSolverSheet = false
            self.activeWebView = nil
            let handler = self.completionHandler
            self.completionHandler = nil
            handler?(success)
        }
    }

    /// Called when user taps Done on solver sheet
    @MainActor
    public func userDidCompleteChallenge() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            self.syncCookiesAndComplete(cookies: cookies, success: true)
        }
    }

    @MainActor
    public func cancel() {
        cancelCurrentSession()
    }

    private func cancelCurrentSession() {
        pollTimer?.cancel()
        pollTimer = nil
        let handler = completionHandler
        completionHandler = nil
        isPresentingSolverSheet = false
        activeWebView = nil
        handler?(false)
    }
}
