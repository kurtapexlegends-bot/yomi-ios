import Foundation
import WebKit
import Observation
import YomiCore

/// Coordinates automated headless Cloudflare Turnstile solving and user-facing interactive captcha sheets.
@Observable
public final class CloudflareSolver: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = CloudflareSolver()

    /// State indicating whether an interactive captcha solver modal sheet needs to be shown.
    public var isPresentingSolverSheet: Bool = false
    public var activeChallengeUrl: URL?

    private var activeWebView: WKWebView?
    private var completionHandler: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    /// Attempts to solve a Cloudflare challenge, first headlessly, falling back to an interactive sheet if needed.
    @MainActor
    public func resolveChallenge(for url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.activeChallengeUrl = url
            self.completionHandler = { success in
                self.isPresentingSolverSheet = false
                self.activeWebView = nil
                continuation.resume(returning: success)
            }

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.customUserAgent = NetworkBridge.defaultUserAgent
            webView.navigationDelegate = self
            self.activeWebView = webView

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            webView.load(request)

            // If not solved within 7 seconds headlessly, present interactive UI to user
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                if self.activeWebView != nil && !self.isPresentingSolverSheet {
                    self.isPresentingSolverSheet = true
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inspect current page title and cookies to verify if challenge passed
        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self = self else { return }
            let title = (result as? String) ?? ""

            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let hasClearance = cookies.contains { $0.name == "cf_clearance" || $0.name == "__cf_bm" }
                let isPastChallenge = !title.contains("Just a moment...") && !title.contains("Attention Required")

                if hasClearance && isPastChallenge {
                    // Synchronize cookies into foundation URLSession storage
                    for cookie in cookies {
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                    self.completionHandler?(true)
                    self.completionHandler = nil
                }
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isPresentingSolverSheet {
            // Keep open for user retry
        } else {
            completionHandler?(false)
            completionHandler = nil
        }
    }

    /// Called by user when dismissing or completing the solver sheet manually.
    @MainActor
    public func userDidCompleteChallenge() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            self?.completionHandler?(true)
            self?.completionHandler = nil
            self?.isPresentingSolverSheet = false
        }
    }

    @MainActor
    public func cancel() {
        completionHandler?(false)
        completionHandler = nil
        isPresentingSolverSheet = false
        activeWebView = nil
    }
}
