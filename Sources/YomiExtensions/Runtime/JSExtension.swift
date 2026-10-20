import Foundation
import JavaScriptCore
import YomiCore

/// Executes community JavaScript manga scrapers inside an isolated JavaScriptCore sandbox.
public final class JSExtension: SourceProtocol, @unchecked Sendable {
    public let manifest: SourceManifest
    public let scriptContent: String

    private let executionQueue = DispatchQueue(label: "com.yomi.jsextension.\(UUID().uuidString)", qos: .userInitiated)

    public init(manifest: SourceManifest, scriptContent: String) {
        self.manifest = manifest
        self.scriptContent = scriptContent
    }

    /// Creates and configures an isolated JSContext with all bridges installed.
    private func makeContext() throws -> JSContext {
        guard let context = JSContext() else {
            throw YomiError.storageError("Failed to initialize JavaScriptCore context")
        }

        context.exceptionHandler = { ctx, exception in
            let errorMsg = exception?.toString() ?? "Unknown JS Exception"
            print("[JSExtension Error - \(self.manifest.name)]: \(errorMsg)")
        }

        // Install Bridges
        HTMLBridge.inject(into: context)
        CryptoBridge.inject(into: context)
        NetworkBridge.inject(into: context)

        // Evaluate Extension Script
        context.evaluateScript(scriptContent)
        return context
    }

    /// Evaluates an async JavaScript function expression and waits for Promise fulfillment.
    private func executeAsync(script: String) async throws -> JSValue {
        return try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                do {
                    let context = try self.makeContext()
                    
                    let wrapper = """
                    (async () => {
                        return await (\(script));
                    })()
                    """
                    
                    guard let promise = context.evaluateScript(wrapper) else {
                        continuation.resume(throwing: YomiError.jsonParsingError("Failed to evaluate script wrapper"))
                        return
                    }

                    // Attach JS handlers to the returned Promise
                    let onFulfilled: @convention(block) (JSValue) -> Void = { val in
                        continuation.resume(returning: val)
                    }
                    let onRejected: @convention(block) (JSValue) -> Void = { err in
                        let errMsg = err.toString() ?? "JS Promise Rejected"
                        if errMsg.contains("__CLOUDFLARE_BLOCKED__") {
                            let urlPart = errMsg.components(separatedBy: "__CLOUDFLARE_BLOCKED__:").last ?? ""
                            if let url = URL(string: urlPart) {
                                continuation.resume(throwing: YomiError.cloudflareChallengeRequired(url: url))
                                return
                            }
                        }
                        continuation.resume(throwing: YomiError.networkError(errMsg))
                    }

                    promise.invokeMethod("then", withArguments: [
                        unsafeBitCast(onFulfilled, to: AnyObject.self),
                        unsafeBitCast(onRejected, to: AnyObject.self)
                    ])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - SourceProtocol Implementation

    public func getFilters() -> [Filter] {
        guard let context = try? makeContext() else { return [] }
        let jsCall = """
        (() => {
            try {
                if (typeof Extension !== 'undefined' && typeof Extension.getFilters === 'function') {
                    return Extension.getFilters();
                }
            } catch (e) {}
            return [];
        })()
        """
        guard let res = context.evaluateScript(jsCall), !res.isUndefined, !res.isNull else { return [] }
        guard let list = res.toArray() as? [[String: Any]] else { return [] }

        return list.compactMap { (dict: [String: Any]) -> Filter? in
            guard let type = dict["type"] as? String,
                  let id = dict["id"] as? String,
                  let name = dict["name"] as? String else { return nil }

            switch type {
            case "select":
                let values = dict["values"] as? [String] ?? []
                let selectedIndex = (dict["selectedIndex"] as? NSNumber)?.intValue ?? (dict["selectedIndex"] as? Int ?? 0)
                return Filter.select(id: id, name: name, values: values, selectedIndex: selectedIndex)
            case "triState":
                let stateRaw = (dict["state"] as? NSNumber)?.intValue ?? (dict["state"] as? Int ?? 0)
                let state = TriState(rawValue: stateRaw) ?? .ignored
                return Filter.triState(id: id, name: name, state: state)
            case "sort":
                let values = dict["values"] as? [String] ?? []
                let selectedIndex = (dict["selectedIndex"] as? NSNumber)?.intValue ?? (dict["selectedIndex"] as? Int ?? 0)
                let ascending = dict["ascending"] as? Bool ?? false
                return Filter.sort(id: id, name: name, values: values, selectedIndex: selectedIndex, ascending: ascending)
            case "text":
                let state = dict["state"] as? String ?? ""
                return Filter.text(id: id, name: name, state: state)
            default:
                return nil
            }
        }
    }

    public func getPopularManga(page: Int) async throws -> MangaPageResult {
        let script = "Extension.getPopularManga(\(page))"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }
        return parseMangaPageResult(from: result)
    }

    public func getLatestUpdates(page: Int) async throws -> MangaPageResult {
        let script = "Extension.getLatestUpdates(\(page))"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }
        return parseMangaPageResult(from: result)
    }

    public func searchManga(query: String, filters: [Filter], page: Int) async throws -> MangaPageResult {
        let escapedQuery = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        var filterDicts: [[String: Any]] = []
        for filter in filters {
            switch filter {
            case .select(let id, let name, let values, let selectedIndex):
                filterDicts.append(["type": "select", "id": id, "name": name, "values": values, "selectedIndex": selectedIndex])
            case .triState(let id, let name, let state):
                filterDicts.append(["type": "triState", "id": id, "name": name, "state": state.rawValue])
            case .sort(let id, let name, let values, let selectedIndex, let ascending):
                filterDicts.append(["type": "sort", "id": id, "name": name, "values": values, "selectedIndex": selectedIndex, "ascending": ascending])
            case .text(let id, let name, let state):
                filterDicts.append(["type": "text", "id": id, "name": name, "state": state])
            }
        }
        let filterJson: String
        if let data = try? JSONSerialization.data(withJSONObject: filterDicts),
           let str = String(data: data, encoding: .utf8) {
            filterJson = str
        } else {
            filterJson = "[]"
        }

        let script = "Extension.searchManga.length <= 2 ? Extension.searchManga(\"\(escapedQuery)\", \(page)) : Extension.searchManga(\"\(escapedQuery)\", \(filterJson), \(page))"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }
        return parseMangaPageResult(from: result)
    }

    public func getMangaDetails(manga: Manga) async throws -> Manga {
        let escapedUrl = manga.url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "Extension.getMangaDetails(\"\(escapedUrl)\")"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }

        var updated = manga
        if let dict = result.toDictionary() as? [String: Any] {
            if let title = dict["title"] as? String, !title.isEmpty { updated.title = title }
            if let author = dict["author"] as? String { updated.author = author }
            if let artist = dict["artist"] as? String { updated.artist = artist }
            if let desc = dict["description"] as? String { updated.description = desc }
            if let genres = dict["genres"] as? [String] { updated.genres = genres }
            if let thumb = dict["thumbnailUrl"] as? String { updated.thumbnailUrl = thumb }
            if let statusInt = dict["status"] as? Int, let st = MangaStatus(rawValue: statusInt) {
                updated.status = st
            }
        }
        return updated
    }

    public func getChapterList(manga: Manga) async throws -> [Chapter] {
        let escapedUrl = manga.url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "Extension.getChapterList(\"\(escapedUrl)\")"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }

        guard let array = result.toArray() as? [[String: Any]] else {
            return []
        }

        var chapters: [Chapter] = []
        for (index, dict) in array.enumerated() {
            let url = dict["url"] as? String ?? ""
            let name = dict["name"] as? String ?? "Chapter \(index + 1)"
            let scanlator = dict["scanlator"] as? String
            let chNum = (dict["chapterNumber"] as? NSNumber)?.floatValue ?? Float(index + 1)
            let dateUpload = (dict["dateUpload"] as? Double).flatMap { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date()

            let chapter = Chapter(
                mangaId: manga.id ?? 0,
                url: url,
                name: name,
                scanlator: scanlator,
                chapterNumber: chNum,
                sourceOrder: index,
                dateFetch: Date(),
                dateUpload: dateUpload
            )
            chapters.append(chapter)
        }
        return chapters
    }

    public func getPageList(chapter: Chapter) async throws -> [ReaderPage] {
        let escapedUrl = chapter.url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "Extension.getPageList(\"\(escapedUrl)\")"
        let result = try await executeWithCloudflareRecovery {
            try await self.executeAsync(script: script)
        }

        guard let array = result.toArray() as? [[String: Any]] else {
            return []
        }

        return array.enumerated().compactMap { idx, item in
            guard let url = item["url"] as? String else { return nil }
            let headers = item["headers"] as? [String: String] ?? [:]
            return ReaderPage(index: idx, url: url, imageUrl: url, headers: headers)
        }
    }

    public func getImageData(page: ReaderPage) async throws -> Data {
        let targetUrlStr = page.imageUrl ?? page.url
        guard let url = URL(string: targetUrlStr) else {
            throw YomiError.networkError("Invalid page image URL: \(targetUrlStr)")
        }

        var request = URLRequest(url: url)
        request.setValue(NetworkBridge.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        let host = url.host?.lowercased() ?? ""
        if host.contains("readdetectiveconan.com") || host.contains("mangapill.com") {
            request.setValue("https://mangapill.com/", forHTTPHeaderField: "Referer")
        } else if host.contains("mangakakalot") || host.contains("mangakakalove") || host.contains("2xstorage") || host.contains("waitst") {
            request.setValue("https://www.mangakakalove.com/", forHTTPHeaderField: "Referer")
        } else {
            var base = manifest.baseUrl
            if !base.hasSuffix("/") { base += "/" }
            request.setValue(base, forHTTPHeaderField: "Referer")
        }

        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        for (k, v) in page.headers {
            if k.lowercased() == "referer" {
                var ref = v
                if ref.contains("2xstorage") || ref.contains("mangakakalot") || ref.contains("mangakakalove") || ref.contains("waitst") {
                    ref = "https://www.mangakakalove.com/"
                } else if !ref.hasSuffix("/") && (ref.hasPrefix("http://") || ref.hasPrefix("https://")) && !ref.dropFirst(8).contains("/") {
                    ref += "/"
                }
                request.setValue(ref, forHTTPHeaderField: k)
            } else {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                if CloudflareSolver.shared.shouldUseWebViewFetch(for: url),
                   let data = await WebViewFetchService.shared.fetchData(request) {
                    return data
                }
                throw YomiError.httpError(statusCode: httpResponse.statusCode, body: nil)
            }
            return data
        } catch {
            // Cloudflare also protects some image CDNs. Retry through the verified WebKit session
            // before surfacing an HTTP/network error to the reader.
            if CloudflareSolver.shared.shouldUseWebViewFetch(for: url),
               let data = await WebViewFetchService.shared.fetchData(request) {
                return data
            }
            throw error
        }
    }

    // MARK: - Helpers

    private func executeWithCloudflareRecovery<T>(_ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch YomiError.cloudflareChallengeRequired(let url) {
            let solved = await CloudflareSolver.shared.resolveChallenge(for: url)
            guard solved else {
                throw YomiError.cloudflareChallengeRequired(url: url)
            }
            // Give the shared URLSession a moment to observe the freshly synced clearance cookies.
            try? await Task.sleep(nanoseconds: 600_000_000)
            return try await block()
        }
    }

    private func parseMangaPageResult(from value: JSValue) -> MangaPageResult {
        guard let dict = value.toDictionary() as? [String: Any],
              let mangasArray = dict["mangas"] as? [[String: Any]] else {
            return MangaPageResult(mangas: [], hasNextPage: false)
        }

        let mangas: [Manga] = mangasArray.compactMap { item in
            guard let url = item["url"] as? String,
                  let title = item["title"] as? String else { return nil }
            let thumb = item["thumbnailUrl"] as? String
            return Manga(
                sourceId: manifest.id,
                url: url,
                title: title,
                status: .unknown,
                thumbnailUrl: thumb
            )
        }
        let hasNext = dict["hasNextPage"] as? Bool ?? false
        return MangaPageResult(mangas: mangas, hasNextPage: hasNext)
    }
}
