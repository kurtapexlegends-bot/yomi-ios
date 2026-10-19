import Foundation
import JavaScriptCore
import YomiCore

public enum NetworkBridge {
    public static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    /// Injects synchronous HTTP request capabilities and a modern fetch wrapper into JSContext.
    public static func inject(into context: JSContext) {
        
        let nativeFetchBlock: @convention(block) (String, String?) -> [String: Any] = { urlString, optionsJson in
            var normalizedUrl = urlString
            if normalizedUrl.contains("mangakakalot") {
                // The legacy .com domain is dead (522) and the canonical host is www.mangakakalot.gg.
                normalizedUrl = normalizedUrl
                    .replacingOccurrences(of: "://www.mangakakalot.com", with: "://www.mangakakalot.gg")
                    .replacingOccurrences(of: "://mangakakalot.com", with: "://www.mangakakalot.gg")
                    .replacingOccurrences(of: "://mangakakalot.gg", with: "://www.mangakakalot.gg")
            }

            guard let url = URL(string: normalizedUrl) else {
                return ["status": 400, "error": "Invalid URL string: \(urlString)"]
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")

            // Forward clearance cookies stored in HTTPCookieStorage
            if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                for (k, v) in cookieHeaders {
                    request.setValue(v, forHTTPHeaderField: k)
                }
            }

            // Parse optional fetch options (headers, method, body)
            if let optionsJson = optionsJson,
               let data = optionsJson.data(using: .utf8),
               let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let method = options["method"] as? String {
                    request.httpMethod = method.uppercased()
                }
                if let headers = options["headers"] as? [String: String] {
                    for (k, v) in headers {
                        request.setValue(v, forHTTPHeaderField: k)
                    }
                }
                if let body = options["body"] as? String {
                    request.httpBody = body.data(using: .utf8)
                }
            }

            let semaphore = DispatchSemaphore(value: 0)
            var resultDict: [String: Any] = [:]

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { semaphore.signal() }

                if let error = error {
                    resultDict = ["status": 0, "error": error.localizedDescription]
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    resultDict = ["status": 0, "error": "Invalid HTTP response"]
                    return
                }

                let statusCode = httpResponse.statusCode
                var headersMap: [String: String] = [:]
                for (k, v) in httpResponse.allHeaderFields {
                    headersMap["\(k)".lowercased()] = "\(v)"
                }

                let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let loweredBody = bodyString.lowercased()
                let serverHeader = headersMap["server"]?.lowercased() ?? ""
                let isMitigatedChallenge = headersMap["cf-mitigated"]?.lowercased() == "challenge"
                let challengeMarkers = [
                    "cf-browser-verification",
                    "challenge-platform",
                    "just a moment",
                    "attention required",
                    "enable javascript and cookies",
                    "challenges.cloudflare.com",
                    "cf_chl_opt",
                    "cf-chl"
                ]
                let hasChallengeMarker = challengeMarkers.contains { loweredBody.contains($0) }

                // Cloudflare challenge detection. MangaKakalot answers with an empty 403 body and
                // only the `cf-mitigated: challenge` header, so header-based detection is required.
                let isCloudflare = isMitigatedChallenge ||
                    (serverHeader.contains("cloudflare") && (statusCode == 403 || statusCode == 429 || statusCode == 503)) ||
                    ((statusCode == 403 || statusCode == 429 || statusCode == 503) && hasChallengeMarker)

                resultDict = [
                    "status": statusCode,
                    "headers": headersMap,
                    "body": bodyString,
                    "isCloudflare": isCloudflare
                ]
            }

            task.resume()
            _ = semaphore.wait(timeout: .now() + 25)

            return resultDict
        }

        context.setObject(nativeFetchBlock, forKeyedSubscript: "__yomi_nativeFetch" as NSString)

        // Inject standard JavaScript `fetch` polyfill leveraging native bridge
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
                    headers: {
                        get: (key) => resp.headers[key.toLowerCase()] || null
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
}
