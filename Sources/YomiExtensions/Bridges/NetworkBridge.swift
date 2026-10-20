import Foundation
import JavaScriptCore
import YomiCore

public enum NetworkBridge {
    public static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Injects synchronous HTTP request capabilities and a modern fetch wrapper into JSContext.
    public static func inject(into context: JSContext) {
        let nativeFetchBlock: @convention(block) (String, String?) -> [String: Any] = { urlString, optionsJson in
            guard var url = URL(string: normalizeURLString(urlString)) else {
                return ["status": 400, "error": "Invalid URL string: \(urlString)"]
            }

            // Canonicalize MangaKakalot domains to non-challenged mirror (mangakakalove.com)
            let rawHost = url.host?.lowercased() ?? ""
            if rawHost == "mangakakalot.com" || rawHost.hasSuffix(".mangakakalot.com") || rawHost == "mangakakalot.gg" || rawHost == "www.mangakakalot.gg" || rawHost == "mangakakalove.com" || rawHost == "www.mangakakalove.com" {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                components?.host = "www.mangakakalove.com"
                if let p = components?.path, p.hasPrefix("/chapter/") {
                    components?.path = "/manga/" + p.dropFirst("/chapter/".count)
                }
                if let canonical = components?.url { url = canonical }
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")

            // Forward clearance cookies stored in HTTPCookieStorage.
            if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            // Always ensure an appropriate Referer header is provided
            if request.value(forHTTPHeaderField: "Referer") == nil {
                let host = url.host?.lowercased() ?? ""
                if host.contains("mangakakalot") || host.contains("mangakakalove") || host.contains("2xstorage") || host.contains("waitst") {
                    request.setValue("https://www.mangakakalove.com/", forHTTPHeaderField: "Referer")
                } else if host.contains("readdetectiveconan.com") || host.contains("mangapill.com") {
                    request.setValue("https://mangapill.com/", forHTTPHeaderField: "Referer")
                } else if host.contains("asurascans") || host.contains("asuracomic") {
                    request.setValue("https://asurascans.com/", forHTTPHeaderField: "Referer")
                } else if host.contains("flamecomics") {
                    request.setValue("https://flamecomics.xyz/", forHTTPHeaderField: "Referer")
                } else if let scheme = url.scheme, !host.isEmpty {
                    request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
                }
            }

            // Parse optional fetch options (headers, method, body).
            if let optionsJson,
               let data = optionsJson.data(using: .utf8),
               let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                if let method = options["method"] as? String {
                    request.httpMethod = method.uppercased()
                }
                if let headers = options["headers"] as? [String: String] {
                    for (key, value) in headers {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }
                if let body = options["body"] as? String {
                    request.httpBody = body.data(using: .utf8)
                }
            }

            var result = performURLSessionFetch(request)

            // URLSession can present a valid cf_clearance cookie and still be rejected because
            // Cloudflare binds clearance to the browser TLS fingerprint. For hosts already
            // verified in WebKit, replay the request inside the same WebKit session.
            if result["isCloudflare"] as? Bool == true,
               CloudflareSolver.shared.shouldUseWebViewFetch(for: url),
               let webKitResult = WebViewFetchService.fetchSync(request) {
                let webKitChallenge = webKitResult["isCloudflare"] as? Bool == true
                if !webKitChallenge, (webKitResult["status"] as? Int ?? 0) > 0 {
                    result = webKitResult
                }
            }

            return result
        }

        context.setObject(nativeFetchBlock, forKeyedSubscript: "__yomi_nativeFetch" as NSString)

        // Inject standard JavaScript `fetch` polyfill leveraging native bridge.
        let polyfillScript = """
        function fetch(url, options = {}) {
            return new Promise((resolve, reject) => {
                const resp = __yomi_nativeFetch(url, JSON.stringify(options));
                if (resp.status === undefined) {
                    return reject(new Error("Network request timed out"));
                }
                if (resp.error) {
                    return reject(new Error(resp.error));
                }
                if (resp.isCloudflare) {
                    return reject(new Error("__CLOUDFLARE_BLOCKED__:" + url));
                }
                resolve({
                    status: resp.status,
                    ok: resp.status >= 200 && resp.status < 300,
                    url: resp.url || url,
                    headers: {
                        get: (key) => resp.headers && resp.headers[key.toLowerCase()] || null
                    },
                    text: () => Promise.resolve(resp.body),
                    json: () => {
                        try {
                            return Promise.resolve(JSON.parse(resp.body));
                        } catch(e) {
                            return reject(e);
                        }
                    }
                });
            });
        }
        """
        context.evaluateScript(polyfillScript)
    }

    private static func normalizeURLString(_ value: String) -> String {
        var normalized = value
        if normalized.contains("mangakakalot") || normalized.contains("mangakakalove") {
            normalized = normalized
                .replacingOccurrences(of: "://www.mangakakalot.com", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://mangakakalot.com", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://www.mangakakalot.gg", with: "://www.mangakakalove.com")
                .replacingOccurrences(of: "://mangakakalot.gg", with: "://www.mangakakalove.com")
            if normalized.contains("mangakakalove.com/chapter/") {
                normalized = normalized.replacingOccurrences(of: "mangakakalove.com/chapter/", with: "mangakakalove.com/manga/")
            }
        }
        return normalized
    }

    private static func performURLSessionFetch(_ request: URLRequest) -> [String: Any] {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedFetchResult()

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                box.set(["status": 0, "error": error.localizedDescription])
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                box.set(["status": 0, "error": "Invalid HTTP response"])
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                headers["\(key)".lowercased()] = "\(value)"
            }

            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let isCloudflare = CloudflareResponseDetector.isChallenge(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: body
            )

            box.set([
                "status": httpResponse.statusCode,
                "headers": headers,
                "body": body,
                "url": httpResponse.url?.absoluteString ?? request.url?.absoluteString ?? "",
                "isCloudflare": isCloudflare
            ])
        }.resume()

        _ = semaphore.wait(timeout: .now() + 25)
        return box.value ?? ["status": 0, "error": "Network request timed out"]
    }
}

private final class LockedFetchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any]?

    func set(_ value: [String: Any]) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    var value: [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
