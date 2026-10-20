import Foundation

#if canImport(WebKit)
import WebKit

/// A serialized, headless WebKit transport for hosts that have passed the interactive
/// Cloudflare challenge.
///
/// `URLSession` can carry `cf_clearance` cookies, but Cloudflare also fingerprints the TLS and
/// HTTP/2 stack that obtained them. On several manga hosts the clearance is valid only inside
/// WebKit, so URLSession keeps receiving `403 cf-mitigated: challenge`. This service replays a
/// request with the page's own `fetch` implementation in a hidden WKWebView sharing the solver's
/// cookie store, which makes the transport match the browser that solved the challenge.
///
/// Requests are processed one at a time because WKWebView navigation and JavaScript evaluation
/// are stateful. Extension calls originate on background JSC queues, so a synchronous bridge is
/// exposed for NetworkBridge; main-thread callers should use the async `enqueue` API.
public final class WebViewFetchService: NSObject, WKNavigationDelegate, @unchecked Sendable {
    public static let shared = WebViewFetchService()

    private struct Job {
        let request: URLRequest
        let continuation: CheckedContinuation<[String: Any]?, Never>
    }

    private var jobs: [Job] = []
    private var isProcessing = false
    private var webView: WKWebView?
    private var loadedOrigin: URL?
    private var navigationContinuation: CheckedContinuation<Bool, Never>?
    private var navigationTimeout: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // MARK: - Synchronous bridge

    /// Runs a WebKit fetch from a background extension queue. Returns nil on the main thread to
    /// avoid deadlocking the main run loop, or when WebKit cannot complete the request.
    public static func fetchSync(_ request: URLRequest, timeout: TimeInterval = 28) -> [String: Any]? {
        guard !Thread.isMainThread else { return nil }
        return runSync(request: request, timeout: timeout)
    }

    /// Fetches raw bytes through WebKit. Used for protected page images that reject URLSession.
    public static func fetchDataSync(_ request: URLRequest, timeout: TimeInterval = 30) -> Data? {
        guard !Thread.isMainThread else { return nil }
        guard let result = runSync(request: request, timeout: timeout),
              let base64 = result["bodyBase64"] as? String,
              let data = Data(base64Encoded: base64),
              !data.isEmpty else {
            return nil
        }
        return data
    }

    /// Async image fetch used by extension code that can await. This is safe to call from the
    /// main actor because WebKit work is already hopped to it.
    public func fetchData(_ request: URLRequest) async -> Data? {
        guard let result = await enqueue(request),
              let base64 = result["bodyBase64"] as? String,
              let data = Data(base64Encoded: base64),
              !data.isEmpty else {
            return nil
        }
        return data
    }

    private static func runSync(request: URLRequest, timeout: TimeInterval) -> [String: Any]? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox<[String: Any]?>(nil)
        Task { @MainActor in
            let result = await WebViewFetchService.shared.enqueue(request)
            box.set(result)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return box.value
    }

    // MARK: - Async queue

    @MainActor
    public func enqueue(_ request: URLRequest) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            jobs.append(Job(request: request, continuation: continuation))
            processNextJob()
        }
    }

    @MainActor
    private func processNextJob() {
        guard !isProcessing, !jobs.isEmpty else { return }
        isProcessing = true
        let job = jobs.removeFirst()

        Task { @MainActor in
            let result = await self.execute(job.request)
            job.continuation.resume(returning: result)
            self.isProcessing = false
            self.processNextJob()
        }
    }

    @MainActor
    private func execute(_ request: URLRequest) async -> [String: Any]? {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let origin = CloudflareSolver.originURL(from: url) else {
            return nil
        }

        guard await loadOrigin(origin) else { return nil }
        return await evaluateFetch(request: request)
    }

    // MARK: - Origin loading

    @MainActor
    private func ensureWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        view.customUserAgent = NetworkBridge.defaultUserAgent
        view.navigationDelegate = self
        view.isHidden = true
        webView = view
        return view
    }

    @MainActor
    private func loadOrigin(_ origin: URL) async -> Bool {
        if loadedOrigin == origin, webView != nil {
            return true
        }

        let view = ensureWebView()
        loadedOrigin = nil

        // Resolve any previous navigation wait so a canceled request can never hang a caller.
        navigationTimeout?.cancel()
        navigationTimeout = nil
        navigationContinuation?.resume(returning: false)
        navigationContinuation = nil

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            navigationContinuation = continuation

            var request = URLRequest(url: origin)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            view.load(request)

            navigationTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishNavigation(success: false)
            }
        }

        if success {
            loadedOrigin = origin
        }
        return success
    }

    @MainActor
    private func finishNavigation(success: Bool) {
        navigationTimeout?.cancel()
        navigationTimeout = nil
        let continuation = navigationContinuation
        navigationContinuation = nil
        continuation?.resume(returning: success)
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(success: true)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(success: false)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishNavigation(success: false)
    }

    // MARK: - Page-context fetch

    @MainActor
    private func evaluateFetch(request: URLRequest) async -> [String: Any]? {
        guard let view = webView, let url = request.url else { return nil }

        let headers = request.allHTTPHeaderFields ?? [:]
        let method = request.httpMethod ?? "GET"
        let bodyBase64 = request.httpBody?.base64EncodedString() ?? ""

        let script = """
        const options = {
            method: method,
            headers: headers,
            credentials: 'include',
            redirect: 'follow'
        };
        if (bodyBase64 && bodyBase64.length > 0) {
            const bytes = Uint8Array.from(atob(bodyBase64), c => c.charCodeAt(0));
            options.body = bytes;
        }
        const response = await fetch(url, options);
        const buffer = await response.arrayBuffer();
        const bytes = new Uint8Array(buffer);
        let binary = '';
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
            binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        const responseHeaders = {};
        response.headers.forEach((value, key) => { responseHeaders[key.toLowerCase()] = value; });
        return JSON.stringify({
            status: response.status,
            url: response.url,
            headers: responseHeaders,
            bodyBase64: binary
        });
        """

        let args: [String: Any] = [
            "url": url.absoluteString,
            "method": method,
            "headers": headers,
            "bodyBase64": bodyBase64
        ]

        return await withCheckedContinuation { continuation in
            let hasResumed = LockedFlag()
            let finish: (Result<Any, Error>) -> Void = { result in
                guard hasResumed.claim() else { return }
                switch result {
                case .success(let value):
                    continuation.resume(returning: Self.decode(value: value))
                case .failure:
                    continuation.resume(returning: nil)
                }
            }

            view.callAsyncJavaScript(script, arguments: args, in: nil, in: .page) { result in
                finish(result)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                guard hasResumed.claim() else { return }
                continuation.resume(returning: nil)
            }
        }
    }

    private static func decode(value: Any) -> [String: Any]? {
        let jsonString: String
        if let string = value as? String {
            jsonString = string
        } else if let dictionary = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let string = String(data: data, encoding: .utf8) {
            jsonString = string
        } else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? Int else {
            return nil
        }

        let headers = object["headers"] as? [String: String] ?? [:]
        let base64 = object["bodyBase64"] as? String ?? ""
        let bodyData = Data(base64Encoded: base64) ?? Data()
        let body = String(data: bodyData, encoding: .utf8) ?? ""
        let isChallenge = CloudflareResponseDetector.isChallenge(
            statusCode: status,
            headers: headers,
            body: body
        )

        return [
            "status": status,
            "headers": headers,
            "body": body,
            "bodyBase64": base64,
            "url": object["url"] as? String ?? "",
            "isCloudflare": isChallenge
        ]
    }
}

// MARK: - Small thread-safe helpers

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        self.stored = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Value) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

#else

public final class WebViewFetchService: NSObject, @unchecked Sendable {
    public static let shared = WebViewFetchService()
    private override init() { super.init() }
    public static func fetchSync(_ request: URLRequest, timeout: TimeInterval = 28) -> [String: Any]? { nil }
    public static func fetchDataSync(_ request: URLRequest, timeout: TimeInterval = 30) -> Data? { nil }
    public func fetchData(_ request: URLRequest) async -> Data? { nil }
    public func enqueue(_ request: URLRequest) async -> [String: Any]? { nil }
}

#endif
