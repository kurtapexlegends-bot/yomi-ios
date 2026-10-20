import XCTest
import JavaScriptCore
@testable import YomiCore
@testable import YomiExtensions

final class ExtensionBridgeTests: XCTestCase {
    func testHTMLAndCryptoBridgeExecution() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }

        HTMLBridge.inject(into: context)
        CryptoBridge.inject(into: context)

        // Test Native HTML Parser
        let htmlSample = "<div class='manga-title'>Chainsaw Man</div>"
        let script = "__yomi_text(\"\(htmlSample)\", \".manga-title\")"
        let textResult = context.evaluateScript(script)
        XCTAssertEqual(textResult?.toString(), "Chainsaw Man")

        // Test Crypto SHA256 Hash
        let hashScript = "__yomi_sha256('yomi')"
        let hashResult = context.evaluateScript(hashScript)
        XCTAssertNotNil(hashResult?.toString())
        XCTAssertEqual(hashResult?.toString().count, 64)
    }

    func testMangaDexSourceManifest() {
        let source = MangaDexSource()
        XCTAssertEqual(source.manifest.id, MangaDexSource.sourceId)
        XCTAssertEqual(source.manifest.name, "MangaDex")
        XCTAssertEqual(source.manifest.lang, "en")
        XCTAssertTrue(source.manifest.supportsLatest)
        XCTAssertFalse(source.manifest.isNsfw)
    }

    func testMangaPillSourceManifest() {
        let source = MangaPillSource()
        XCTAssertEqual(source.manifest.id, MangaPillSource.sourceId)
        XCTAssertEqual(source.manifest.name, "MangaPill")
        XCTAssertEqual(source.manifest.lang, "en")
        XCTAssertTrue(source.manifest.supportsLatest)
        XCTAssertFalse(source.manifest.isNsfw)
        XCTAssertEqual(source.manifest.baseUrl, "https://mangapill.com")
    }

    func testKeiyoushiRepoUrlNormalization() {
        let repoManager = RepoManager.shared

        // Test index.min.json mapped to modern index.json
        let minJsonUrl = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"
        let normalizedMin = repoManager.normalizeRepoUrl(minJsonUrl)
        XCTAssertEqual(normalizedMin, RepoManager.keiyoushiRepoURL)

        // Test URL with trailing punctuation (period from sentence copy-paste)
        let punctuatedUrl = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json."
        let normalizedPunct = repoManager.normalizeRepoUrl(punctuatedUrl)
        XCTAssertEqual(normalizedPunct, RepoManager.keiyoushiRepoURL)

        // Test URL with angle brackets or quotes
        let bracketedUrl = "<https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json>"
        let normalizedBracket = repoManager.normalizeRepoUrl(bracketedUrl)
        XCTAssertEqual(normalizedBracket, RepoManager.keiyoushiRepoURL)

        // Test github repository URL mapped to raw repo index
        let githubUrl = "https://github.com/keiyoushi/extensions"
        let normalizedGithub = repoManager.normalizeRepoUrl(githubUrl)
        XCTAssertEqual(normalizedGithub, RepoManager.keiyoushiRepoURL)

        // Test URL without index.json suffix
        let bareUrl = "https://example.com/repo/"
        let normalizedBare = repoManager.normalizeRepoUrl(bareUrl)
        XCTAssertEqual(normalizedBare, "https://example.com/repo/index.json")
    }

    func testKeiyoushiV2RepoSchemaParsing() throws {
        let sampleJson = """
        {
            "name": "Keiyoushi",
            "contact": { "website": "https://keiyoushi.github.io" },
            "extensionList": {
                "extensions": [
                    {
                        "name": "MangaSee",
                        "packageName": "eu.kanade.tachiyomi.extension.en.mangasee",
                        "resources": {
                            "iconUrl": "https://example.com/mangasee.png",
                            "apkUrl": "https://example.com/mangasee.apk"
                        },
                        "versionName": "1.4.3",
                        "contentWarning": "CONTENT_WARNING_SAFE",
                        "sources": [
                            {
                                "id": "5530823947742715441",
                                "name": "MangaSee",
                                "language": "en",
                                "homeUrl": "https://mangasee123.com"
                            }
                        ]
                    },
                    {
                        "name": "Outdated App",
                        "packageName": "eu.kanade.tachiyomi.extension.all.keiyoushi",
                        "versionName": "1.0.0",
                        "contentWarning": "CONTENT_WARNING_SAFE"
                    }
                ]
            }
        }
        """

        let data = sampleJson.data(using: .utf8)!
        let parsed = try RepoManager.shared.parseRepoData(data, sourceUrl: "https://example.com/index.json")

        XCTAssertEqual(parsed.name, "Keiyoushi")
        XCTAssertEqual(parsed.website, "https://keiyoushi.github.io")
        // "Outdated App" warning stub should be automatically filtered out
        XCTAssertEqual(parsed.extensions.count, 1)

        let pkg = parsed.extensions[0]
        XCTAssertEqual(pkg.name, "MangaSee")
        XCTAssertEqual(pkg.id, 5530823947742715441)
        XCTAssertEqual(pkg.lang, "en")
        XCTAssertEqual(pkg.baseUrl, "https://mangasee123.com")
        XCTAssertEqual(pkg.version, "1.4.3")
        XCTAssertFalse(pkg.isNsfw)
    }

    func testExtensionManagerBuiltInSources() {
        let manager = ExtensionManager.shared
        manager.reloadInstalledSources()

        let hasMangaPill = manager.installedSources.contains { $0.manifest.id == MangaPillSource.sourceId }
        let hasMangaDex = manager.installedSources.contains { $0.manifest.id == MangaDexSource.sourceId }

        XCTAssertTrue(hasMangaPill, "ExtensionManager must register MangaPillSource")
        XCTAssertTrue(hasMangaDex, "ExtensionManager must register MangaDexSource")
    }

    func testSourceFiltersAvailability() {
        let pillSource = MangaPillSource()
        let pillFilters = pillSource.getFilters()
        XCTAssertEqual(pillFilters.count, 3)
        XCTAssertEqual(pillFilters[0].id, "type")
        XCTAssertEqual(pillFilters[1].id, "status")
        XCTAssertEqual(pillFilters[2].id, "genre")
        XCTAssertTrue(pillFilters.allSatisfy { $0.isDefault })

        let dexSource = MangaDexSource()
        let dexFilters = dexSource.getFilters()
        XCTAssertEqual(dexFilters.count, 3)
        XCTAssertEqual(dexFilters[0].id, "status")
        XCTAssertEqual(dexFilters[1].id, "contentRating")
        XCTAssertEqual(dexFilters[2].id, "sort")
        XCTAssertTrue(dexFilters.allSatisfy { $0.isDefault })
    }

    func testMangakakalotScraperGeneration() {
        let pkg = RemoteExtensionPackage(
            id: 99999,
            name: "MangaKakalot",
            lang: "en",
            baseUrl: "https://www.mangakakalot.gg",
            scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: pkg)
        XCTAssertTrue(script.contains("/manga-list/hot-manga?page="))
        XCTAssertTrue(script.contains("/manga-list/latest-manga?page="))
        XCTAssertTrue(script.contains("/search/story/"))
        XCTAssertTrue(script.contains("getFilters: function()"))
        XCTAssertTrue(script.contains("type: 'select'") || script.contains("type: \"select\""))

        // End-to-end: verify JSExtension runtime parses generated scraper's filters correctly
        let manifest = SourceManifest(
            id: pkg.id,
            name: pkg.name,
            lang: pkg.lang,
            baseUrl: pkg.baseUrl
        )
        let jsExt = JSExtension(manifest: manifest, scriptContent: script)
        let filters = jsExt.getFilters()
        XCTAssertEqual(filters.count, 3)
        XCTAssertEqual(filters[0].id, "genre")
        XCTAssertEqual(filters[1].id, "status")
        XCTAssertEqual(filters[2].id, "sort")
    }

    func testMangakakalotHtmlParsing() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)
        CryptoBridge.inject(into: context)
        NetworkBridge.inject(into: context)

        let pkg = RemoteExtensionPackage(
            id: 99999,
            name: "MangaKakalot",
            lang: "en",
            baseUrl: "https://www.mangakakalot.gg",
            scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: pkg)
        context.evaluateScript(script)

        let sampleHtml = """
        <div id="contentstory">
            <div class="itemupdate first">
                <a class="tooltip cover bookmark_check" href="https://www.mangakakalot.gg/manga/solo-leveling">
                    <img src="https://example.com/solo.webp" data-src="https://example.com/solo.webp" alt="Solo Leveling">
                </a>
                <ul>
                    <li>
                        <h3><a href="https://www.mangakakalot.gg/manga/solo-leveling">Solo Leveling</a></h3>
                    </li>
                </ul>
            </div>
        </div>
        """
        context.setObject(sampleHtml, forKeyedSubscript: "__sampleHtml" as NSString)
        let parseScript = "Extension.parseMangaList(__sampleHtml)"
        guard let result = context.evaluateScript(parseScript), !result.isUndefined, !result.isNull else {
            XCTFail("Extension.parseMangaList returned nil or undefined")
            return
        }
        let dict = result.toDictionary() as? [String: Any]
        let mangas = dict?["mangas"] as? [[String: Any]]
        XCTAssertEqual(mangas?.count, 1)
        XCTAssertEqual(mangas?.first?["title"] as? String, "Solo Leveling")
        XCTAssertEqual(mangas?.first?["url"] as? String, "https://www.mangakakalot.gg/manga/solo-leveling")
        XCTAssertEqual(mangas?.first?["thumbnailUrl"] as? String, "https://example.com/solo.webp")
    }

    func testMangaDexUUIDExtraction() {
        let regex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
        let sampleUrls = [
            "/title/f98660a0-81e2-499c-84e1-4c6e10096573",
            "/title/f98660a0-81e2-499c-84e1-4c6e10096573/one-piece",
            "https://mangadex.org/title/f98660a0-81e2-499c-84e1-4c6e10096573/one-piece"
        ]
        for url in sampleUrls {
            let match = regex?.firstMatch(in: url, range: NSRange(url.startIndex..., in: url))
            XCTAssertNotNil(match, "UUID regex must match \(url)")
            if let match = match, let range = Range(match.range, in: url) {
                XCTAssertEqual(String(url[range]), "f98660a0-81e2-499c-84e1-4c6e10096573")
            }
        }
    }

    func testJSExtensionGetFilters() {
        let manifest = SourceManifest(
            id: 88888,
            name: "TestJSExtension",
            baseUrl: "https://example.com"
        )
        // Test standard const Extension declaration
        let constScript = """
        const Extension = {
            getFilters: function() {
                return [
                    { type: "select", id: "genre", name: "Genre", values: ["All", "Action", "Drama"], selectedIndex: 0 },
                    { type: "triState", id: "completed", name: "Completed", state: 1 },
                    { type: "sort", id: "sort", name: "Sort By", values: ["Popularity", "Latest"], selectedIndex: 1, ascending: true },
                    { type: "text", id: "author", name: "Author", state: "Oda" }
                ];
            }
        };
        """
        let constExt = JSExtension(manifest: manifest, scriptContent: constScript)
        let constFilters = constExt.getFilters()
        XCTAssertEqual(constFilters.count, 4)
        XCTAssertEqual(constFilters[0].id, "genre")
        XCTAssertEqual(constFilters[0].name, "Genre")
        XCTAssertEqual(constFilters[1].id, "completed")
        XCTAssertEqual(constFilters[1].name, "Completed")
        XCTAssertEqual(constFilters[2].id, "sort")
        XCTAssertEqual(constFilters[2].name, "Sort By")
        XCTAssertEqual(constFilters[3].id, "author")
        XCTAssertEqual(constFilters[3].name, "Author")

        // Also test var Extension declaration
        let varScript = """
        var Extension = {
            getFilters: function() {
                return [
                    { type: "select", id: "lang", name: "Language", values: ["All", "EN"], selectedIndex: 0 }
                ];
            }
        };
        """
        let varExt = JSExtension(manifest: manifest, scriptContent: varScript)
        XCTAssertEqual(varExt.getFilters().count, 1)

        // Also test empty / missing getFilters
        let emptyScript = "const Extension = {};"
        let emptyExt = JSExtension(manifest: manifest, scriptContent: emptyScript)
        XCTAssertTrue(emptyExt.getFilters().isEmpty)
    }
}


