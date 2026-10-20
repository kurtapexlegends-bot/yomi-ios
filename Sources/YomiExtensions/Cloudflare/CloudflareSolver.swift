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

    private var activeContinuation: CheckedContinuation<Bool, Never>?
    private var pendingChallenges: [PendingChallenge] = []
    private var pollTimer: Task<Void, Never>?
    private var challengeHost: String = ""
    /// Invalidates cookie-store callbacks from a challenge whose sheet has already closed.
    private var challengeGeneration: Int = 0

    private struct PendingChallenge {
        let url: URL
        let host: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// Hosts whose `cf_clearance` cookie was issued by this WebKit session. Requests for these
    /// hosts may be replayed through `WebViewFetchService` when URLSession is still blocked by
    /// Cloudflare's TLS/fingerprint checks.
    private let verifiedHostsLock = NSLock()
    private var verifiedHosts: Set<String> = []

    private override init() {
        super.init()
    }

    /// Resolves a Cloudflare anti-bot challenge by presenting the interactive solver sheet.
    ///
    /// Concurrent requests are queued instead of cancelling each other. A batch refresh can hit
    /// several protected hosts at once, and the previous implementation surfaced only the last
    /// challenge while silently failing every other request.
    @MainActor
    public func resolveChallenge(for url: URL) async -> Bool {
        // Present the challenge URL (keeping the page path for HTML content so Turnstile triggers,
        // or using origin for binary/API endpoints).
        let target = CloudflareHostPolicy.challengeURL(from: url)
        let host = target.host?.lowercased() ?? url.host?.lowercased() ?? ""

        if isPresentingSolverSheet {
            return await withCheckedContinuation { continuation in
                pendingChallenges.append(
                    PendingChallenge(url: target, host: host, continuation: continuation)
                )
            }
        }

        return await withCheckedContinuation { continuation in
            beginChallenge(origin: target, host: host, continuation: continuation)
        }
    }

    @MainActor
    private func beginChallenge(
        origin: URL,
        host: String,
        continuation: CheckedContinuation<Bool, Never>
    ) {
        challengeGeneration += 1
        activeChallengeUrl = origin
        challengeHost = host
        statusMessage = "Solve the verification below, then tap Done."
        activeContinuation = continuation
        isPresentingSolverSheet = true

        // Purge any stale/expired clearance cookies for this host so the poller does not
        // falsely succeed on a dead session before the user even interacts.
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let store = WKWebsiteDataStore.default().httpCookieStore
            for cookie in cookies where Self.isClearanceCookie(cookie, forHost: host) {
                store.delete(cookie)
            }
        }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where Self.isClearanceCookie(cookie, forHost: host) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }

        // Poll the cookie store while the sheet is presented.
        pollTimer = Task { @MainActor [weak self] in
            for _ in 0..<80 { // Poll up to ~120 seconds
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self = self, self.isPresentingSolverSheet else { return }
                self.inspectChallengeStatus()
            }
            // Timed out without clearance: resolve this caller and offer the next queued host.
            guard let self = self, self.isPresentingSolverSheet else { return }
            self.finishActiveChallenge(success: false)
        }
    }

    /// Returns the scheme://host origin of a URL, discarding path/query.
    public static func originURL(from url: URL) -> URL? {
        guard let scheme = url.scheme, let rawHost = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = CloudflareHostPolicy.canonicalHost(rawHost)
        components.port = url.port
        components.path = "/"
        return components.url
    }

    /// Marks a host as having received a valid clearance cookie. Safe to call from background
    /// extension queues; the set is guarded by a lock because WebKit callbacks are main-actor.
    public func markHostVerified(_ host: String) {
        let normalized = CloudflareHostPolicy.normalizedHost(host)
        guard !normalized.isEmpty else { return }
        verifiedHostsLock.lock()
        verifiedHosts.insert(normalized)
        verifiedHostsLock.unlock()
    }

    /// True when requests for this URL should be attempted through the WebKit transport.
    public func shouldUseWebViewFetch(for url: URL) -> Bool {
        guard let host = url.host else { return false }
        return isHostVerified(host)
    }

    public func isHostVerified(_ host: String) -> Bool {
        let normalized = CloudflareHostPolicy.normalizedHost(host)
        guard !normalized.isEmpty else { return false }
        verifiedHostsLock.lock()
        defer { verifiedHostsLock.unlock() }
        return verifiedHosts.contains { CloudflareHostPolicy.matches(host: normalized, domain: $0) }
    }

    /// Used by tests and when the user explicitly clears web data.
    public func clearVerifiedHosts() {
        verifiedHostsLock.lock()
        verifiedHosts.removeAll()
        verifiedHostsLock.unlock()
    }

    /// Clears both verified-host state and stale clearance cookies so the next protected request
    /// presents a fresh verification sheet instead of silently replaying an expired session.
    @MainActor
    public func resetVerification() {
        clearVerifiedHosts()
        WebViewFetchService.shared.resetSession()

        for cookie in HTTPCookieStorage.shared.cookies ?? [] where cookie.name == "cf_clearance" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let store = WKWebsiteDataStore.default().httpCookieStore
            for cookie in cookies where cookie.name == "cf_clearance" {
                store.delete(cookie)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        handleNavigationFinished(webView: webView)
    }

    @MainActor
    public func handleNavigationFinished(webView: WKWebView) {
        if let currentURL = webView.url {
            let path = currentURL.path.lowercased()
            let title = (webView.title ?? "").lowercased()
            let isChallenged = path.contains("challenge-platform")
                || title.contains("just a moment")
                || title.contains("attention required")
                || title.contains("checking your browser")

            if !isChallenged && !title.isEmpty {
                // Page successfully navigated to genuine content. Verify clearance cookie exists.
                inspectChallengeStatus(forceCompletion: false)
                return
            }
        }
        inspectChallengeStatus(forceCompletion: false)
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
        cancelAllChallenges()
    }

    // MARK: - Cookie inspection

    public func inspectChallengeStatus(forceCompletion: Bool = false) {
        // Capture the target host and session on the main actor; the callback runs on a WebKit queue.
        let host = challengeHost
        let generation = challengeGeneration
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let clearance = cookies.filter { Self.isClearanceCookie($0, forHost: host) }

            if !clearance.isEmpty || forceCompletion {
                Task { @MainActor [weak self] in
                    guard let self = self,
                          self.challengeGeneration == generation,
                          self.activeContinuation != nil else { return }
                    self.syncCookiesAndComplete(cookies: cookies, success: true, host: host)
                }
            }
        }
    }

    /// A clearance cookie must be named `cf_clearance`, belong to the challenged host,
    /// and not be expired.
    /// `__cf_bm` is intentionally ignored: it is issued to every visitor and does not indicate
    /// that the challenge was solved.
    static func isClearanceCookie(_ cookie: HTTPCookie, forHost host: String) -> Bool {
        guard cookie.name == "cf_clearance" else { return false }
        if let expiresDate = cookie.expiresDate, expiresDate < Date() {
            return false
        }
        let cookieDomain = CloudflareHostPolicy.normalizedHost(cookie.domain)
        guard !cookieDomain.isEmpty else { return true }
        if host.isEmpty { return true }
        return CloudflareHostPolicy.matches(host: host, domain: cookieDomain)
    }

    @MainActor
    private func syncCookiesAndComplete(cookies: [HTTPCookie], success: Bool, host: String) {
        let clearanceCookies = cookies.filter { $0.name == "cf_clearance" }
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        if success {
            markHostVerified(host)
            // The cookie domain is the most reliable scope for replaying clearance. Mark it as
            // well as the exact challenge host so subdomains (www., m., etc.) are covered.
            for cookie in clearanceCookies {
                markHostVerified(cookie.domain)
            }
        }

        finishActiveChallenge(success: success)
    }

    @MainActor
    private func finishActiveChallenge(success: Bool) {
        pollTimer?.cancel()
        pollTimer = nil
        challengeGeneration += 1

        let continuation = activeContinuation
        activeContinuation = nil
        isPresentingSolverSheet = false
        activeWebView = nil
        statusMessage = nil
        challengeHost = ""

        continuation?.resume(returning: success)
        startNextQueuedChallenge()
    }

    /// Resolves queued requests that the newly verified host already covers, then presents the
    /// next distinct host. Requests for the same host never make the user solve two sheets.
    @MainActor
    private func startNextQueuedChallenge() {
        while let next = pendingChallenges.first {
            pendingChallenges.removeFirst()
            if isHostVerified(next.host) {
                next.continuation.resume(returning: true)
                continue
            }
            beginChallenge(origin: next.url, host: next.host, continuation: next.continuation)
            return
        }
    }

    @MainActor
    private func cancelAllChallenges() {
        pollTimer?.cancel()
        pollTimer = nil
        challengeGeneration += 1

        let active = activeContinuation
        activeContinuation = nil
        let pending = pendingChallenges
        pendingChallenges.removeAll()

        isPresentingSolverSheet = false
        activeWebView = nil
        statusMessage = nil
        challengeHost = ""

        active?.resume(returning: false)
        for challenge in pending {
            challenge.continuation.resume(returning: false)
        }
    }
}
