import Foundation
import WebKit
import Observation
import YomiCore

/// Coordinates interactive and automated Cloudflare challenge resolution and cookie synchronization.
///
/// Flow:
/// 1. A JS extension request is blocked by Cloudflare and raises `__CLOUDFLARE_BLOCKED__`.
/// 2. The origin homepage of the challenged host is loaded in a `WKWebView` sheet so the
///    managed challenge / Turnstile widget can run.
/// 3. The solver polls the `WKHTTPCookieStore` until a host-scoped `cf_clearance` cookie exists.
///    (`__cf_bm` is NOT sufficient: Cloudflare sets it for every visitor, so trusting it made the
///    app silently "succeed" before the challenge was ever solved.)
/// 4. Clearance cookies are copied into `HTTPCookieStorage.shared` so `URLSession` can replay them.
@Observable
public final class CloudflareSolver: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = CloudflareSolver()

    /// State indicating whether an interactive captcha solver modal sheet needs to be shown.
    public var isPresentingSolverSheet: Bool = false
    public var activeChallengeUrl: URL?
    public var activeWebView: WKWebView?
    /// Human readable status shown inside the solver sheet.
    public var statusMessage: String?

    private var completionHandler: ((Bool) -> Void)?
    private var pollTimer: Task<Void, Never>?
    private var challengeHost: String = ""

    private override init() {
        super.init()
    }

    /// Resolves a Cloudflare anti-bot challenge by presenting the interactive solver sheet.
    @MainActor
    public func resolveChallenge(for url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            // Terminate any previous pending challenge so its caller never hangs.
            self.cancelCurrentSession(notify: true)

            // Always present the site origin: Cloudflare serves an empty, unsolvable body for
            // direct API/JSON requests, but a full challenge page for top-level navigation.
            let origin = Self.originURL(from: url) ?? url
            self.activeChallengeUrl = origin
            self.challengeHost = origin.host?.lowercased() ?? url.host?.lowercased() ?? ""
            self.statusMessage = "Solve the verification below, then tap Done."
            self.completionHandler = { success in
                self.pollTimer?.cancel()
                self.pollTimer = nil
                self.isPresentingSolverSheet = false
                self.activeWebView = nil
                continuation.resume(returning: success)
            }

            self.isPresentingSolverSheet = true

            // Poll the cookie store while the sheet is presented.
            self.pollTimer = Task { @MainActor [weak self] in
                for _ in 0..<80 { // Poll up to ~120 seconds
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self = self, self.isPresentingSolverSheet else { return }
                    self.inspectChallengeStatus()
                }
                // Timed out without clearance: resolve so callers are never left hanging.
                guard let self = self, self.isPresentingSolverSheet else { return }
                self.statusMessage = "Timed out waiting for verification. Tap Done to retry."
                self.complete(success: false)
            }
        }
    }

    /// Returns the scheme://host origin of a URL, discarding path/query.
    public static func originURL(from url: URL) -> URL? {
        guard let scheme = url.scheme, let rawHost = url.host else { return nil }
        var host = rawHost.lowercased()
        // MangaKakalot's legacy .com domain is dead; always solve on the live .gg host.
        if host.contains("mangakakalot") {
            host = "www.mangakakalot.gg"
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/"
        return components.url
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inspectChallengeStatus()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Keep the interactive web view alive so the user can refresh or solve Turnstile.
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Transient failures: keep the sheet active.
    }

    /// Called when the user taps Done on the solver sheet.
    @MainActor
    public func userDidCompleteChallenge() {
        inspectChallengeStatus(forceCompletion: true)
    }

    @MainActor
    public func cancel() {
        cancelCurrentSession(notify: true)
    }

    // MARK: - Cookie inspection

    private func inspectChallengeStatus(forceCompletion: Bool = false) {
        // Capture the target host on the main actor; the callback runs on a WebKit queue.
        let host = challengeHost
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let clearance = cookies.filter { Self.isClearanceCookie($0, forHost: host) }

            if !clearance.isEmpty {
                DispatchQueue.main.async {
                    self.syncCookiesAndComplete(cookies: cookies, success: true)
                }
            } else if forceCompletion {
                DispatchQueue.main.async {
                    // Nothing verified yet: keep the sheet open so the user can retry.
                    self.statusMessage = "Verification not detected yet. Complete the challenge, then tap Done again."
                }
            }
        }
    }

    /// A clearance cookie must be named `cf_clearance` and belong to the challenged host.
    /// `__cf_bm` is intentionally ignored: it is issued to every visitor and does not indicate
    /// that the challenge was solved.
    static func isClearanceCookie(_ cookie: HTTPCookie, forHost host: String) -> Bool {
        guard cookie.name == "cf_clearance" else { return false }
        let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cookieDomain.isEmpty else { return true }
        if host.isEmpty { return true }
        return host == cookieDomain || host.hasSuffix("." + cookieDomain) || cookieDomain.hasSuffix("." + host)
    }

    private func syncCookiesAndComplete(cookies: [HTTPCookie], success: Bool) {
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        complete(success: success)
    }

    private func complete(success: Bool) {
        let handler = completionHandler
        completionHandler = nil
        handler?(success)
    }

    private func cancelCurrentSession(notify: Bool) {
        pollTimer?.cancel()
        pollTimer = nil
        let handler = completionHandler
        completionHandler = nil
        isPresentingSolverSheet = false
        activeWebView = nil
        statusMessage = nil
        if notify {
            handler?(false)
        }
    }
}
