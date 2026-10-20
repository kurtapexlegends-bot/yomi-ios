import XCTest
@testable import YomiExtensions
import Foundation

final class CloudflareTransportTests: XCTestCase {

    func testHostPolicyMatchesSubdomainsAndParentDomains() {
        XCTAssertTrue(CloudflareHostPolicy.matches(host: "www.mangakakalot.gg", domain: "mangakakalot.gg"))
        XCTAssertTrue(CloudflareHostPolicy.matches(host: "mangakakalot.gg", domain: "www.mangakakalot.gg"))
        XCTAssertTrue(CloudflareHostPolicy.matches(host: "m.mangakakalot.gg", domain: "mangakakalot.gg"))
        XCTAssertFalse(CloudflareHostPolicy.matches(host: "notmangakakalot.gg", domain: "mangakakalot.gg"))
        XCTAssertFalse(CloudflareHostPolicy.matches(host: "example.com", domain: "mangakakalot.gg"))
    }

    func testHostPolicyCanonicalizesDeadMangaKakalotHost() {
        XCTAssertEqual(CloudflareHostPolicy.canonicalHost("mangakakalot.com"), "www.mangakakalot.gg")
        XCTAssertEqual(CloudflareHostPolicy.canonicalHost("WWW.MANGAKAKALOT.COM"), "www.mangakakalot.gg")
        XCTAssertEqual(CloudflareHostPolicy.canonicalHost("www.mangakakalot.gg"), "www.mangakakalot.gg")
    }

    func testCfMitigatedHeaderIsAChallengeEvenWithEmptyBody() {
        let detected = CloudflareResponseDetector.isChallenge(
            statusCode: 403,
            headers: ["server": "cloudflare", "cf-mitigated": "challenge"],
            body: ""
        )
        XCTAssertTrue(detected)
    }

    func testNormalOriginResponseIsNotAChallenge() {
        let detected = CloudflareResponseDetector.isChallenge(
            statusCode: 200,
            headers: ["server": "cloudflare", "content-type": "text/html"],
            body: "<html><body>Manga chapter page</body></html>"
        )
        XCTAssertFalse(detected)
    }

    func testChallengeMarkersAreDetectedWithoutCfMitigatedHeader() {
        let detected = CloudflareResponseDetector.isChallenge(
            statusCode: 503,
            headers: ["server": "cloudflare"],
            body: "<html><script src='https://challenges.cloudflare.com/turnstile'></script></html>"
        )
        XCTAssertTrue(detected)
    }

    func testOrdinaryServerErrorIsNotCloudflareChallenge() {
        let detected = CloudflareResponseDetector.isChallenge(
            statusCode: 500,
            headers: ["server": "nginx"],
            body: "internal server error"
        )
        XCTAssertFalse(detected)
    }
}
