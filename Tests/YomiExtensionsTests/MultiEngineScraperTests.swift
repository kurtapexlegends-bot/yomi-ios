import XCTest
import JavaScriptCore
@testable import YomiCore
@testable import YomiExtensions

final class MultiEngineScraperTests: XCTestCase {

    func testScraperScriptGeneratorArchetypeSelection() {
        let repoManager = RepoManager.shared

        // 1. MangaKakalot
        let mkPkg = RemoteExtensionPackage(
            id: 1, name: "MangaKakalot", lang: "en", baseUrl: "https://mangakakalot.com", scriptUrl: ""
        )
        let mkScript = repoManager.generateScraperScript(for: mkPkg)
        XCTAssertTrue(mkScript.contains("mangakakalove.com"))

        // 2. Asura Scans
        let asuraPkg = RemoteExtensionPackage(
            id: 2, name: "Asura Scans", lang: "en", baseUrl: "https://asuracomic.net", scriptUrl: "", packageName: "eu.kanade.tachiyomi.extension.en.asurascans"
        )
        let asuraScript = repoManager.generateScraperScript(for: asuraPkg)
        XCTAssertTrue(asuraScript.contains("a[href*='/comics/']"))

        // 3. Flame Comics
        let flamePkg = RemoteExtensionPackage(
            id: 3, name: "Flame Comics", lang: "en", baseUrl: "https://flamecomics.xyz", scriptUrl: "", packageName: "eu.kanade.tachiyomi.extension.en.flamecomics"
        )
        let flameScript = repoManager.generateScraperScript(for: flamePkg)
        XCTAssertTrue(flameScript.contains("a[href*='/series/']"))

        // 4. Universal Fallback
        let otherPkg = RemoteExtensionPackage(
            id: 4, name: "Custom Manga", lang: "en", baseUrl: "https://example.com", scriptUrl: ""
        )
        let otherScript = repoManager.generateScraperScript(for: otherPkg)
        XCTAssertTrue(otherScript.contains("BASE_URL = \"https://example.com\""))
    }

    func testMadaraScraperParsing() {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)

        let asuraPkg = RemoteExtensionPackage(
            id: 2, name: "Asura Scans", lang: "en", baseUrl: "https://asurascans.com", scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: asuraPkg)
        context.evaluateScript(script)

        let html = """
        <div class="page-item-detail">
            <a href="https://asurascans.com/comics/solo-leveling" title="Solo Leveling">
                <img src="https://cdn.asurascans.com/covers/solo.webp" alt="Solo Leveling">
            </a>
            <div class="post-title">
                <h3><a href="https://asurascans.com/comics/solo-leveling">Solo Leveling</a></h3>
            </div>
        </div>
        """
        context.setObject(html, forKeyedSubscript: "__asuraHtml" as NSString)
        let result = context.evaluateScript("Extension.parseMangaList(__asuraHtml)")
        guard let dict = result?.toDictionary() as? [String: Any],
              let mangas = dict["mangas"] as? [[String: Any]],
              let first = mangas.first else {
            XCTFail("Failed to parse Asura manga list")
            return
        }

        XCTAssertEqual(first["title"] as? String, "Solo Leveling")
        XCTAssertEqual(first["url"] as? String, "https://asurascans.com/comics/solo-leveling")
        XCTAssertEqual(first["thumbnailUrl"] as? String, "https://cdn.asurascans.com/covers/solo.webp")
    }

    func testUniversalScraperParsing() {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)

        let pkg = RemoteExtensionPackage(
            id: 5, name: "Generic Manga", lang: "en", baseUrl: "https://genericmanga.com", scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: pkg)
        context.evaluateScript(script)

        let html = """
        <div class="grid">
            <div class="card">
                <a href="/manga/one-punch-man">
                    <img data-src="https://genericmanga.com/opm.jpg" alt="One Punch Man">
                    <h3 class="title">One Punch Man</h3>
                </a>
            </div>
        </div>
        """
        context.setObject(html, forKeyedSubscript: "__genHtml" as NSString)
        let result = context.evaluateScript("Extension.parseMangaList(__genHtml)")
        guard let dict = result?.toDictionary() as? [String: Any],
              let mangas = dict["mangas"] as? [[String: Any]],
              let first = mangas.first else {
            XCTFail("Failed to parse generic manga list")
            return
        }

        XCTAssertEqual(first["title"] as? String, "One Punch Man")
        XCTAssertEqual(first["url"] as? String, "https://genericmanga.com/manga/one-punch-man")
        XCTAssertEqual(first["thumbnailUrl"] as? String, "https://genericmanga.com/opm.jpg")
    }
}
