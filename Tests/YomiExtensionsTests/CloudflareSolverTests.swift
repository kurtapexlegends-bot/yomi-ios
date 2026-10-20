import XCTest
@testable import YomiExtensions
import Foundation

final class CloudflareSolverTests: XCTestCase {

    private func makeCookie(name: String, domain: String, value: String = "test-value") -> HTTPCookie {
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600)
        ]
        return HTTPCookie(properties: properties)!
    }

    func testClearanceCookieRequiresCfClearanceName() {
        let clearance = makeCookie(name: "cf_clearance", domain: ".mangakakalot.gg")
        XCTAssertTrue(CloudflareSolver.isClearanceCookie(clearance, forHost: "www.mangakakalot.gg"))
    }

    func testBotManagementCookieIsNotTreatedAsClearance() {
        // __cf_bm is issued to every visitor; trusting it previously made the solver
        // report success before the challenge was actually solved.
        let botManagement = makeCookie(name: "__cf_bm", domain: ".mangakakalot.gg")
        XCTAssertFalse(CloudflareSolver.isClearanceCookie(botManagement, forHost: "www.mangakakalot.gg"))
    }

    func testClearanceCookieForAnotherHostIsRejected() {
        let otherHost = makeCookie(name: "cf_clearance", domain: ".example.com")
        XCTAssertFalse(CloudflareSolver.isClearanceCookie(otherHost, forHost: "www.mangakakalot.gg"))
    }

    func testClearanceCookieAcceptsParentDomain() {
        let clearance = makeCookie(name: "cf_clearance", domain: "mangakakalot.gg")
        XCTAssertTrue(CloudflareSolver.isClearanceCookie(clearance, forHost: "www.mangakakalot.gg"))
    }

    func testOriginURLCanonicalizesDeadMangaKakalotDomain() throws {
        let url = try XCTUnwrap(URL(string: "https://mangakakalot.com/manga-list/hot-manga?page=1"))
        let origin = try XCTUnwrap(CloudflareSolver.originURL(from: url))
        XCTAssertEqual(origin.absoluteString, "https://www.mangakakalot.gg/")
    }

    func testOriginURLDropsPathAndQuery() throws {
        let url = try XCTUnwrap(URL(string: "https://www.mangakakalot.gg/manga/some-title/chapter/1"))
        let origin = try XCTUnwrap(CloudflareSolver.originURL(from: url))
        XCTAssertEqual(origin.absoluteString, "https://www.mangakakalot.gg/")
    }
}
