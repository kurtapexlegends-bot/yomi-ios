import Foundation

/// Centralized Cloudflare challenge detection.
///
/// Different hosts answer in different ways: an empty `403` with `cf-mitigated: challenge`,
/// a `503` interstitial, or a `200` JavaScript challenge page. Keeping the rules in one place
/// prevents the URLSession path and the WebKit fallback from disagreeing.
public enum CloudflareResponseDetector {

    private static let strongBodyMarkers: [String] = [
        "cf-browser-verification",
        "challenge-platform",
        "cf_chl_opt",
        "cf-chl",
        "challenges.cloudflare.com"
    ]

    private static let titleMarkers: [String] = [
        "<title>just a moment...</title>",
        "<title>attention required!",
        "enable javascript and cookies to continue",
        "checking your browser before accessing"
    ]

    public static func isChallenge(statusCode: Int, headers: [String: String], body: String) -> Bool {
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map {
            ($0.key.lowercased(), $0.value.lowercased())
        })

        if normalizedHeaders["cf-mitigated"]?.contains("challenge") == true {
            return true
        }

        let loweredBody = body.lowercased()
        let hasStrongMarker = strongBodyMarkers.contains { loweredBody.contains($0) }
        let hasTitleMarker = titleMarkers.contains { loweredBody.contains($0) }
        let isFailureStatus = statusCode == 403 || statusCode == 429 || statusCode == 503
        let serverSaysCloudflare = (normalizedHeaders["server"] ?? "").contains("cloudflare")

        if hasStrongMarker { return true }
        if hasTitleMarker && (isFailureStatus || loweredBody.contains("cloudflare")) { return true }
        if isFailureStatus && serverSaysCloudflare { return true }
        return false
    }
}
