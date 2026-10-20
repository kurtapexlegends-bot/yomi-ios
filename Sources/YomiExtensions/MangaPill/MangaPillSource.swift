import Foundation
import SwiftSoup
import YomiCore

/// Native high-performance connector for MangaPill (fast, comprehensive mainstream manga catalog).
public final class MangaPillSource: SourceProtocol, Sendable {
    public static let sourceId: Int64 = 10002
    private let baseUrl = "https://mangapill.com"
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    public var manifest: SourceManifest {
        SourceManifest(
            id: Self.sourceId,
            name: "MangaPill",
            lang: "en",
            baseUrl: baseUrl,
            iconUrl: "\(baseUrl)/favicon.ico",
            version: "1.1.0",
            isConfigurable: true,
            supportsLatest: true,
            isNsfw: false
        )
    }

    public func getFilters() -> [Filter] {
        [
            .select(
                id: "type",
                name: "Type",
                values: ["All", "Manga", "Manhwa / Manhua", "Novel", "One-Shot", "Doujinshi", "Oel"],
                selectedIndex: 0
            ),
            .select(
                id: "status",
                name: "Status",
                values: ["All", "Publishing", "Finished", "On Hiatus", "Discontinued"],
                selectedIndex: 0
            ),
            .select(
                id: "genre",
                name: "Genre",
                values: [
                    "All", "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy",
                    "Gender Bender", "Harem", "Historical", "Horror", "Isekai", "Josei",
                    "Magic", "Martial Arts", "Mecha", "Mystery", "Psychological", "Romance",
                    "School", "Sci-Fi", "Seinen", "Shoujo", "Shounen", "Slice of Life",
                    "Sports", "Supernatural", "Thriller", "Tragedy"
                ],
                selectedIndex: 0
            )
        ]
    }

    public init() {}

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseUrl, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 20
        return request
    }

    // MARK: - Search & Discovery

    public func getPopularManga(page: Int) async throws -> MangaPageResult {
        let p = max(1, page)
        let urlString = "\(baseUrl)/mangas/new?page=\(p)"
        return try await fetchMangaListing(from: urlString)
    }

    public func getLatestUpdates(page: Int) async throws -> MangaPageResult {
        let p = max(1, page)
        let urlString = "\(baseUrl)/mangas/new?page=\(p)"
        return try await fetchMangaListing(from: urlString)
    }

    public func searchManga(query: String, filters: [Filter], page: Int) async throws -> MangaPageResult {
        let p = max(1, page)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var queryItems: [String] = ["page=\(p)"]
        if !trimmed.isEmpty {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            queryItems.append("q=\(encoded)")
        }

        for filter in filters {
            switch filter {
            case .select(let id, _, let values, let selectedIndex):
                guard selectedIndex > 0 && selectedIndex < values.count else { continue }
                let val = values[selectedIndex]
                if id == "type" {
                    let paramVal: String
                    if val.contains("Manhwa") { paramVal = "manhua" }
                    else { paramVal = val.lowercased().replacingOccurrences(of: " ", with: "-") }
                    queryItems.append("type=\(paramVal)")
                } else if id == "status" {
                    let paramVal = val.lowercased()
                    queryItems.append("status=\(paramVal)")
                } else if id == "genre" {
                    let paramVal = val.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? val
                    queryItems.append("genre=\(paramVal)")
                }
            default:
                break
            }
        }

        // If neither search query nor filters are specified, browse latest/popular
        if trimmed.isEmpty && queryItems.count == 1 {
            return try await getPopularManga(page: p)
        }
        let queryString = queryItems.joined(separator: "&")
        let urlString = "\(baseUrl)/search?\(queryString)"
        return try await fetchMangaListing(from: urlString)
    }

    // MARK: - Manga Details & Chapters

    public func getMangaDetails(manga: Manga) async throws -> Manga {
        let fullUrl = manga.url.hasPrefix("http") ? manga.url : "\(baseUrl)\(manga.url)"
        guard let url = URL(string: fullUrl) else { throw YomiError.networkError("Invalid manga URL") }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }

        guard let html = String(data: data, encoding: .utf8) else { return manga }
        let doc = try SwiftSoup.parse(html)

        var updated = manga
        let titleEl = try doc.select("h1").first()
        if let title = try titleEl?.text(), !title.isEmpty {
            updated.title = title
        }

        if let descEl = try doc.select("p.text--secondary, p.description, .description").first() {
            let desc = try descEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !desc.isEmpty && !desc.contains("Chapter not found") { updated.description = desc }
        }

        if let coverEl = try doc.select("figure img, .detail--cover img, img").first() {
            let thumb = try coverEl.attr("data-src")
            let fallbackThumb = try coverEl.attr("src")
            let coverUrl = !thumb.isEmpty ? thumb : fallbackThumb
            if let normalized = normalizeImageUrl(coverUrl) { updated.thumbnailUrl = normalized }
        }

        let genreEls = try doc.select("a[href*='/genre/'], .genres a").array()
        let genres = genreEls.compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !genres.isEmpty { updated.genres = genres }

        return updated
    }

    public func getChapterList(manga: Manga) async throws -> [Chapter] {
        let fullUrl = manga.url.hasPrefix("http") ? manga.url : "\(baseUrl)\(manga.url)"
        guard let url = URL(string: fullUrl) else { throw YomiError.networkError("Invalid manga URL") }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }

        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a[href*='/chapters/']").array()

        var chapters: [Chapter] = []
        for (idx, link) in links.enumerated() {
            let href = try link.attr("href")
            guard !href.isEmpty else { continue }
            let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "Chapter \(links.count - idx)" : name

            // Extract chapter number from title or URL
            var chNum: Float = Float(links.count - idx)
            let lower = displayName.lowercased()
            if let range = lower.range(of: "chapter\\s+([0-9]+(?:\\.[0-9]+)?)", options: .regularExpression) {
                let match = String(lower[range])
                let digits = match.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
                if let parsed = Float(digits) {
                    chNum = parsed
                }
            }

            let chapter = Chapter(
                mangaId: manga.id ?? 0,
                url: href,
                name: displayName,
                chapterNumber: chNum,
                sourceOrder: idx,
                dateFetch: Date(),
                dateUpload: Date()
            )
            chapters.append(chapter)
        }

        return chapters
    }

    public func getPageList(chapter: Chapter) async throws -> [ReaderPage] {
        let fullUrl = chapter.url.hasPrefix("http") ? chapter.url : "\(baseUrl)\(chapter.url)"
        guard let url = URL(string: fullUrl) else { throw YomiError.networkError("Invalid chapter URL") }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }

        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let doc = try SwiftSoup.parse(html)
        let imgEls = try doc.select("img.js-page, #reader-area img").array()

        var pages: [ReaderPage] = []
        for (idx, img) in imgEls.enumerated() {
            let dataSrc = try img.attr("data-src")
            let src = try img.attr("src")
            let imgUrl = !dataSrc.isEmpty ? dataSrc : src
            guard !imgUrl.isEmpty, imgUrl.hasPrefix("http") else { continue }

            let page = ReaderPage(
                index: idx,
                url: imgUrl,
                imageUrl: imgUrl,
                headers: ["Referer": baseUrl, "User-Agent": userAgent]
            )
            pages.append(page)
        }

        return pages
    }

    public func getImageData(page: ReaderPage) async throws -> Data {
        guard let targetUrlStr = page.imageUrl ?? Optional(page.url),
              let url = URL(string: targetUrlStr) else {
            throw YomiError.networkError("Invalid page URL")
        }

        var request = URLRequest(url: url)
        request.setValue(baseUrl, forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in page.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }
        return data
    }

    // MARK: - HTML Scraper Helpers

    private func fetchMangaListing(from urlString: String) async throws -> MangaPageResult {
        guard let url = URL(string: urlString) else {
            throw YomiError.networkError("Invalid listing URL: \(urlString)")
        }

        let request = makeRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return MangaPageResult(mangas: [], hasNextPage: false)
        }

        let doc = try SwiftSoup.parse(html)
        let cards = try doc.select(".grid > div, div.grid > div, div:has(> a[href*='/manga/'])").array()

        var mangas: [Manga] = []
        var seenUrls = Set<String>()

        for card in cards {
            guard let linkEl = try card.select("a[href*='/manga/']").first() else { continue }
            let href = try linkEl.attr("href")
            guard !href.isEmpty, !seenUrls.contains(href) else { continue }
            seenUrls.insert(href)

            // Extract title from .font-black, .line-clamp-2, or image alt attribute
            var title = try card.select(".font-black, .line-clamp-2, h3").first()?.text() ?? ""
            if title.isEmpty {
                title = try card.select("img").first()?.attr("alt") ?? ""
            }
            if title.isEmpty {
                title = try card.text().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !title.isEmpty else { continue }

            // Thumbnail extraction
            let imgEl = try card.select("img").first()
            let thumb = try imgEl?.attr("data-src") ?? ""
            let fallbackThumb = try imgEl?.attr("src") ?? ""
            let effectiveThumb = !thumb.isEmpty ? thumb : fallbackThumb
            let normalizedThumb = normalizeImageUrl(effectiveThumb)

            // Status heuristic
            let cardText = try card.text().lowercased()
            let status: MangaStatus = (cardText.contains("completed") || cardText.contains("finished")) ? .completed : .ongoing

            let manga = Manga(
                sourceId: Self.sourceId,
                url: href,
                title: title,
                status: status,
                thumbnailUrl: normalizedThumb
            )
            mangas.append(manga)
        }

        // Fallback to deduplicated links if grid selector didn't match
        if mangas.isEmpty {
            let links = try doc.select("a[href*='/manga/']").array()
            for link in links {
                let href = try link.attr("href")
                guard !href.isEmpty, !seenUrls.contains(href) else { continue }
                let title = try link.select(".font-black").first()?.text() ?? link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                seenUrls.insert(href)

                let imgEl = try link.select("img").first()
                let thumb = try imgEl?.attr("data-src") ?? imgEl?.attr("src") ?? ""
                let normalizedThumb = normalizeImageUrl(thumb)

                let manga = Manga(
                    sourceId: Self.sourceId,
                    url: href,
                    title: title,
                    status: .ongoing,
                    thumbnailUrl: normalizedThumb
                )
                mangas.append(manga)
            }
        }

        let hasNext = mangas.count >= 20
        return MangaPageResult(mangas: mangas, hasNextPage: hasNext)
    }

    private func normalizeImageUrl(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if trimmed.hasPrefix("/") {
            return baseUrl + trimmed
        }
        return "\(baseUrl)/\(trimmed)"
    }
}
