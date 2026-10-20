import Foundation

/// Pure host/domain matching used by the Cloudflare verification pipeline.
///
/// Kept separate from WebKit so it can be unit-tested on every platform and reused by
/// both the cookie solver and the WebKit-backed fetch fallback.
public enum CloudflareHostPolicy {

    public static func normalizedHost(_ raw: String?) -> String {
        guard var host = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else {
            return ""
        }
        while host.hasPrefix(".") { host.removeFirst() }
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    /// Applies known dead-domain replacements before a challenge is presented.
    public static func canonicalHost(_ raw: String) -> String {
        var host = normalizedHost(raw)
        if host == "mangakakalot.com" || host.hasSuffix(".mangakakalot.com")
            || host == "mangakakalot.tv" || host.hasSuffix(".mangakakalot.tv")
            || host == "mangakakalot.org" || host.hasSuffix(".mangakakalot.org") {
            host = "www.mangakakalot.gg"
        }
        return host
    }

    /// Converts a requested URL into an appropriate URL for interactive Cloudflare verification.
    ///
    /// For binary assets (images, fonts) or direct API endpoints, loading the site origin is preferred
    /// because browsers cannot solve Turnstile on raw binary streams. For HTML webpages (e.g. manga listings,
    /// chapter readers), the actual blocked URL must be presented so Cloudflare triggers its challenge.
    public static func challengeURL(from url: URL) -> URL {
        let path = url.path.lowercased()
        let assetExtensions = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".json", ".js", ".css"]
        let isAsset = assetExtensions.contains { path.hasSuffix($0) } || path.contains("/api/")
        guard let scheme = url.scheme, let rawHost = url.host else { return url }

        let canonical = canonicalHost(rawHost)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = scheme
        components.host = canonical
        components.port = url.port

        if isAsset {
            components.path = "/"
            components.query = nil
        }
        return components.url ?? url
    }

    /// Returns true when `domain` is the same host as `host` or a parent domain of it.
    public static func matches(host: String, domain: String) -> Bool {
        let h = normalizedHost(host)
        let d = normalizedHost(domain)
        guard !h.isEmpty, !d.isEmpty else { return false }
        return h == d || h.hasSuffix("." + d) || d.hasSuffix("." + h)
    }

    public static func isSameSite(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = lhs.host, let right = rhs.host else { return false }
        return matches(host: left, domain: right)
    }
}
