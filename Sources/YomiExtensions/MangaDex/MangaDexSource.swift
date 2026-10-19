import Foundation
import YomiCore

/// Native high-performance connector for the official MangaDex API (v5).
public final class MangaDexSource: SourceProtocol, Sendable {
    public static let sourceId: Int64 = 10001
    private let apiBase = "https://api.mangadex.org"
    private let userAgent = "Yomi/1.0 (iOS; MangaDexSource)"

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    public var manifest: SourceManifest {
        SourceManifest(
            id: Self.sourceId,
            name: "MangaDex",
            lang: "en",
            baseUrl: "https://mangadex.org",
            iconUrl: "https://mangadex.org/favicon.ico",
            version: "2.0.0",
            isConfigurable: true,
            supportsLatest: true,
            isNsfw: false
        )
    }

    public init() {}

    // MARK: - Search & Discovery

    public func getPopularManga(page: Int) async throws -> MangaPageResult {
        let offset = (max(1, page) - 1) * 24
        var components = URLComponents(string: "\(apiBase)/manga")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "order[followedCount]", value: "desc"),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "includes[]", value: "author"),
            URLQueryItem(name: "contentRating[]", value: "safe"),
            URLQueryItem(name: "contentRating[]", value: "suggestive")
        ]
        guard let url = components.url else {
            throw YomiError.networkError("Invalid MangaDex URL components")
        }
        return try await fetchMangaList(from: url.absoluteString)
    }

    public func getLatestUpdates(page: Int) async throws -> MangaPageResult {
        let offset = (max(1, page) - 1) * 24
        var components = URLComponents(string: "\(apiBase)/manga")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "order[latestUploadedChapter]", value: "desc"),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "includes[]", value: "author"),
            URLQueryItem(name: "contentRating[]", value: "safe"),
            URLQueryItem(name: "contentRating[]", value: "suggestive")
        ]
        guard let url = components.url else {
            throw YomiError.networkError("Invalid MangaDex URL components")
        }
        return try await fetchMangaList(from: url.absoluteString)
    }

    public func getFilters() -> [Filter] {
        [
            .select(
                id: "status",
                name: "Status",
                values: ["All", "Ongoing", "Completed", "Hiatus", "Cancelled"],
                selectedIndex: 0
            ),
            .select(
                id: "contentRating",
                name: "Content Rating",
                values: ["Safe & Suggestive", "Safe Only", "Erotica", "All Ratings (incl. NSFW)"],
                selectedIndex: 0
            ),
            .select(
                id: "sort",
                name: "Sort",
                values: ["Most Popular", "Latest Upload", "Title", "Recently Added"],
                selectedIndex: 0
            )
        ]
    }

    public func searchManga(query: String, filters: [Filter], page: Int) async throws -> MangaPageResult {
        let offset = (max(1, page) - 1) * 24
        var components = URLComponents(string: "\(apiBase)/manga")!
        var queryItems = [
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "includes[]", value: "author")
        ]

        var contentRatings = ["safe", "suggestive"]
        var sortParam = ("followedCount", "desc")

        for filter in filters {
            switch filter {
            case .select(let id, _, let values, let selectedIndex):
                guard selectedIndex >= 0 && selectedIndex < values.count else { continue }
                if id == "status" && selectedIndex > 0 {
                    let val = values[selectedIndex].lowercased()
                    queryItems.append(URLQueryItem(name: "status[]", value: val))
                } else if id == "contentRating" {
                    switch selectedIndex {
                    case 1: contentRatings = ["safe"]
                    case 2: contentRatings = ["safe", "suggestive", "erotica"]
                    case 3: contentRatings = ["safe", "suggestive", "erotica", "pornographic"]
                    default: contentRatings = ["safe", "suggestive"]
                    }
                } else if id == "sort" {
                    switch selectedIndex {
                    case 1: sortParam = ("latestUploadedChapter", "desc")
                    case 2: sortParam = ("title", "asc")
                    case 3: sortParam = ("createdAt", "desc")
                    default: sortParam = ("followedCount", "desc")
                    }
                }
            default:
                break
            }
        }

        for rating in contentRatings {
            queryItems.append(URLQueryItem(name: "contentRating[]", value: rating))
        }
        queryItems.append(URLQueryItem(name: "order[\(sortParam.0)]", value: sortParam.1))

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: trimmed))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw YomiError.networkError("Invalid MangaDex URL components")
        }
        return try await fetchMangaList(from: url.absoluteString)
    }

    private func extractMangaId(from urlString: String) -> String {
        if let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range, in: urlString) {
            return String(urlString[range])
        }
        let clean = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return clean.components(separatedBy: "/").last ?? urlString
    }

    public func getMangaDetails(manga: Manga) async throws -> Manga {
        let mangaId = extractMangaId(from: manga.url)
        var components = URLComponents(string: "\(apiBase)/manga/\(mangaId)")!
        components.queryItems = [
            URLQueryItem(name: "includes[]", value: "cover_art"),
            URLQueryItem(name: "includes[]", value: "author"),
            URLQueryItem(name: "includes[]", value: "artist")
        ]
        guard let url = components.url else { throw YomiError.networkError("Invalid MangaDex URL") }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let attributes = dataDict["attributes"] as? [String: Any] else {
            return manga
        }

        var updated = manga
        if let titleDict = attributes["title"] as? [String: String] {
            updated.title = titleDict["en"] ?? titleDict.values.first ?? manga.title
        }
        if let descDict = attributes["description"] as? [String: String] {
            updated.description = descDict["en"] ?? descDict.values.first
        }
        if let statusStr = attributes["status"] as? String {
            switch statusStr.lowercased() {
            case "ongoing": updated.status = .ongoing
            case "completed": updated.status = .completed
            case "hiatus": updated.status = .onHiatus
            case "cancelled": updated.status = .cancelled
            default: updated.status = .unknown
            }
        }
        if let tagsArray = attributes["tags"] as? [[String: Any]] {
            updated.genres = tagsArray.compactMap {
                ($0["attributes"] as? [String: Any])?["name"] as? [String: String]
            }.compactMap { $0["en"] }
        }

        // Parse Author and Artist relationships
        if let rels = dataDict["relationships"] as? [[String: Any]] {
            for rel in rels {
                let type = rel["type"] as? String
                let name = (rel["attributes"] as? [String: Any])?["name"] as? String
                if type == "author" { updated.author = name }
                if type == "artist" { updated.artist = name }
            }
        }

        return updated
    }

    public func getChapterList(manga: Manga) async throws -> [Chapter] {
        let mangaId = extractMangaId(from: manga.url)

        // Attempt fetching English chapters first
        let enChapters = try await fetchChaptersFeed(manga: manga, mangaId: mangaId, englishOnly: true)
        if !enChapters.isEmpty {
            return enChapters
        }

        // Fallback: If 0 English chapters exist, fetch chapters across all languages
        return try await fetchChaptersFeed(manga: manga, mangaId: mangaId, englishOnly: false)
    }

    private func fetchChaptersFeed(manga: Manga, mangaId: String, englishOnly: Bool) async throws -> [Chapter] {
        var chapters: [Chapter] = []
        var offset = 0
        let limit = 100
        var total = 100
        var seenUrls = Set<String>()

        while offset < min(total, 500) {
            var components = URLComponents(string: "\(apiBase)/manga/\(mangaId)/feed")!
            var queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "order[chapter]", value: "desc"),
                URLQueryItem(name: "includes[]", value: "scanlation_group"),
                URLQueryItem(name: "contentRating[]", value: "safe"),
                URLQueryItem(name: "contentRating[]", value: "suggestive"),
                URLQueryItem(name: "contentRating[]", value: "erotica"),
                URLQueryItem(name: "contentRating[]", value: "pornographic")
            ]
            if englishOnly {
                queryItems.append(URLQueryItem(name: "translatedLanguage[]", value: "en"))
            }
            components.queryItems = queryItems
            guard let url = components.url else { break }

            let request = makeRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            var jsonData = data
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if let (retryData, retryResp) = try? await URLSession.shared.data(for: request),
                   let rHttp = retryResp as? HTTPURLResponse, rHttp.statusCode < 400 {
                    jsonData = retryData
                } else {
                    break
                }
            }

            guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let dataList = json["data"] as? [[String: Any]] else {
                break
            }

            total = json["total"] as? Int ?? dataList.count

            for (idx, item) in dataList.enumerated() {
                guard let chId = item["id"] as? String,
                      let attrs = item["attributes"] as? [String: Any] else { continue }

                if seenUrls.contains(chId) { continue }
                seenUrls.insert(chId)

                let extUrl = attrs["externalUrl"] as? String
                let pages = attrs["pages"] as? Int ?? 0

                let chString = attrs["chapter"] as? String ?? ""
                let chNum = Float(chString) ?? -1.0
                let rawTitle = (attrs["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lang = attrs["translatedLanguage"] as? String ?? "en"

                var displayName: String
                if rawTitle.isEmpty {
                    displayName = chString.isEmpty ? "Chapter" : "Chapter \(chString)"
                } else {
                    displayName = rawTitle
                }

                if lang != "en" {
                    displayName = "[\(lang.uppercased())] \(displayName)"
                }

                // Extract scanlator group name from relationships
                var scanlatorName: String?
                if let rels = item["relationships"] as? [[String: Any]] {
                    for rel in rels {
                        if rel["type"] as? String == "scanlation_group",
                           let groupAttrs = rel["attributes"] as? [String: Any],
                           let name = groupAttrs["name"] as? String {
                            scanlatorName = name
                            break
                        }
                    }
                }

                if let ext = extUrl, !ext.isEmpty, pages <= 0 {
                    scanlatorName = "External (\(scanlatorName ?? "Web"))"
                }

                let uploadDateStr = attrs["publishAt"] as? String ?? ""
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let dateUpload = formatter.date(from: uploadDateStr) ?? ISO8601DateFormatter().date(from: uploadDateStr) ?? Date()

                let chapter = Chapter(
                    mangaId: manga.id ?? 0,
                    url: chId,
                    name: displayName,
                    scanlator: scanlatorName,
                    chapterNumber: chNum,
                    sourceOrder: offset + idx,
                    dateFetch: Date(),
                    dateUpload: dateUpload
                )
                chapters.append(chapter)
            }

            offset += limit
            if dataList.isEmpty { break }
        }

        return chapters
    }

    public func getPageList(chapter: Chapter) async throws -> [ReaderPage] {
        let chId = chapter.url.components(separatedBy: "/").last ?? chapter.url
        let urlString = "\(apiBase)/at-home/server/\(chId)"
        guard let url = URL(string: urlString) else { throw YomiError.networkError("Invalid chapter URL") }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            if http.statusCode == 404 {
                throw YomiError.chapterNotFound("MangaDex does not host images for this chapter (external license or removed). Please read this title using MangaPill.")
            }
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseUrl = json["baseUrl"] as? String,
              let chapterDict = json["chapter"] as? [String: Any],
              let hash = chapterDict["hash"] as? String else {
            throw YomiError.jsonParsingError("Failed to parse MangaDex at-home response")
        }

        let originalFiles = chapterDict["data"] as? [String] ?? []
        let dataSaverFiles = chapterDict["dataSaver"] as? [String] ?? []

        if !originalFiles.isEmpty {
            return originalFiles.enumerated().map { idx, fileName in
                let imageUrl = "\(baseUrl)/data/\(hash)/\(fileName)"
                return ReaderPage(index: idx, url: imageUrl, imageUrl: imageUrl)
            }
        } else if !dataSaverFiles.isEmpty {
            return dataSaverFiles.enumerated().map { idx, fileName in
                let imageUrl = "\(baseUrl)/data-saver/\(hash)/\(fileName)"
                return ReaderPage(index: idx, url: imageUrl, imageUrl: imageUrl)
            }
        } else {
            throw YomiError.chapterNotFound("MangaDex does not host image files for this chapter. Please read this title using MangaPill.")
        }
    }

    public func getImageData(page: ReaderPage) async throws -> Data {
        guard let url = URL(string: page.imageUrl ?? page.url) else {
            throw YomiError.networkError("Invalid page URL")
        }
        var request = URLRequest(url: url)
        request.setValue("https://mangadex.org", forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }
        return data
    }

    // MARK: - Internal Parsing

    private func fetchMangaList(from urlString: String) async throws -> MangaPageResult {
        guard let url = URL(string: urlString) else {
            throw YomiError.networkError("Invalid URL: \(urlString)")
        }

        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataList = json["data"] as? [[String: Any]] else {
            return MangaPageResult(mangas: [], hasNextPage: false)
        }

        let total = json["total"] as? Int ?? 0
        let offset = json["offset"] as? Int ?? 0
        let limit = json["limit"] as? Int ?? 24
        let hasNext = (offset + limit) < total

        let mangas: [Manga] = dataList.compactMap { item in
            guard let mangaId = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any] else { return nil }

            let titleDict = attrs["title"] as? [String: String]
            var title = titleDict?["en"] ?? titleDict?.values.first
            if title == nil || title?.isEmpty == true {
                if let altTitles = attrs["altTitles"] as? [[String: String]] {
                    for alt in altTitles {
                        if let t = alt["en"] ?? alt.values.first, !t.isEmpty {
                            title = t
                            break
                        }
                    }
                }
            }

            // Description
            let descDict = attrs["description"] as? [String: String]
            let description = descDict?["en"] ?? descDict?.values.first

            // Status
            var status: MangaStatus = .unknown
            if let statusStr = attrs["status"] as? String {
                switch statusStr.lowercased() {
                case "ongoing": status = .ongoing
                case "completed": status = .completed
                case "hiatus": status = .onHiatus
                case "cancelled": status = .cancelled
                default: status = .unknown
                }
            }

            // Look for cover art file and author in relationships
            var coverUrl: String?
            var authorName: String?
            if let rels = item["relationships"] as? [[String: Any]] {
                for rel in rels {
                    let type = rel["type"] as? String
                    if type == "author" {
                        authorName = (rel["attributes"] as? [String: Any])?["name"] as? String
                    }
                    if type == "cover_art",
                       let coverAttrs = rel["attributes"] as? [String: Any],
                       let fileName = coverAttrs["fileName"] as? String {
                        coverUrl = "https://uploads.mangadex.org/covers/\(mangaId)/\(fileName).512.jpg"
                    }
                }
            }

            return Manga(
                sourceId: Self.sourceId,
                url: mangaId,
                title: title ?? "Untitled Manga",
                author: authorName,
                description: description,
                status: status,
                thumbnailUrl: coverUrl
            )
        }

        return MangaPageResult(mangas: mangas, hasNextPage: hasNext)
    }
}
