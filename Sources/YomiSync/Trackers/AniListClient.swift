import Foundation
import YomiCore

public struct TrackerSearchResult: Identifiable, Sendable {
    public let id: Int64
    public let title: String
    public let coverUrl: String?
    public let totalChapters: Int
    public let trackingUrl: String

    public init(id: Int64, title: String, coverUrl: String? = nil, totalChapters: Int = 0, trackingUrl: String = "") {
        self.id = id
        self.title = title
        self.coverUrl = coverUrl
        self.totalChapters = totalChapters
        self.trackingUrl = trackingUrl
    }
}

/// Client interacting with the AniList GraphQL API for live manga tracking.
public final class AniListClient: Sendable {
    public static let shared = AniListClient()
    private let endpoint = URL(string: "https://graphql.anilist.co")!

    public var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "anilist_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "anilist_access_token") }
    }

    public var isLoggedIn: Bool {
        accessToken != nil && !accessToken!.isEmpty
    }

    public init() {}

    /// Searches AniList for manga matching title query.
    public func searchManga(query: String) async throws -> [TrackerSearchResult] {
        let graphQLQuery = """
        query ($search: String) {
            Page(page: 1, perPage: 10) {
                media(search: $search, type: MANGA) {
                    id
                    title {
                        userPreferred
                        english
                        romaji
                    }
                    coverImage {
                        large
                    }
                    chapters
                    siteUrl
                }
            }
        }
        """

        let variables: [String: Any] = ["search": query]
        let payload: [String: Any] = ["query": graphQLQuery, "variables": variables]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let pageDict = dataDict["Page"] as? [String: Any],
              let mediaList = pageDict["media"] as? [[String: Any]] else {
            return []
        }

        return mediaList.compactMap { item in
            guard let id = item["id"] as? Int64 else { return nil }
            let titleDict = item["title"] as? [String: String]
            let title = titleDict?["userPreferred"] ?? titleDict?["english"] ?? titleDict?["romaji"] ?? "Unknown Title"
            let coverDict = item["coverImage"] as? [String: String]
            let cover = coverDict?["large"]
            let chapters = item["chapters"] as? Int ?? 0
            let siteUrl = item["siteUrl"] as? String ?? "https://anilist.co/manga/\(id)"

            return TrackerSearchResult(id: id, title: title, coverUrl: cover, totalChapters: chapters, trackingUrl: siteUrl)
        }
    }

    /// Updates read chapter progress on AniList.
    public func updateProgress(mediaId: Int64, chapterProgress: Int, status: TrackStatus, score: Double) async throws {
        guard let token = accessToken, !token.isEmpty else {
            throw YomiError.networkError("AniList is not authenticated")
        }

        let aniListStatus: String
        switch status {
        case .reading: aniListStatus = "CURRENT"
        case .completed: aniListStatus = "COMPLETED"
        case .onHold: aniListStatus = "PAUSED"
        case .dropped: aniListStatus = "DROPPED"
        case .planToRead: aniListStatus = "PLANNING"
        case .repeating: aniListStatus = "REPEATING"
        }

        let mutation = """
        mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus, $score: Float) {
            SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status, score: $score) {
                id
                progress
                status
            }
        }
        """

        let variables: [String: Any] = [
            "mediaId": mediaId,
            "progress": chapterProgress,
            "status": aniListStatus,
            "score": score
        ]

        let payload: [String: Any] = ["query": mutation, "variables": variables]
        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw YomiError.httpError(statusCode: http.statusCode, body: nil)
        }
    }
}
