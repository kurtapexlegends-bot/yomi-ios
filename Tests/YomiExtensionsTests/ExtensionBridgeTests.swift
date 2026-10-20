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

    func testMangaKakalotChapterFallbackDOMParsing() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)
        let pkg = RemoteExtensionPackage(
            id: 2528986671771677900,
            name: "MangaKakalot",
            lang: "en",
            baseUrl: "https://www.mangakakalove.com",
            scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: pkg)
        context.evaluateScript(script)

        let sampleHtml = """
        <div class="row-content-chapter">
            <li><a href="https://www.mangakakalove.com/manga/solo-leveling/chapter-10">Chapter 10</a></li>
            <li><a href="https://www.mangakakalove.com/manga/solo-leveling/chapter-9">Chapter 9</a></li>
        </div>
        """
        context.setObject(sampleHtml, forKeyedSubscript: "__sampleHtml" as NSString)
        let testScript = """
        (function() {
            const links = __yomi_selectAll(__sampleHtml, ".row-content-chapter li a, .chapter-list a, .chapter-name, a[href*='/chapter']");
            return links.map((l, i) => ({
                url: __yomi_attr(l, "", "href"),
                name: __yomi_text(l, "")
            }));
        })()
        """
        guard let result = context.evaluateScript(testScript), let chapters = result.toArray() as? [[String: Any]] else {
            XCTFail("Chapter fallback evaluation failed")
            return
        }
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0]["name"] as? String, "Chapter 10")
        XCTAssertEqual(chapters[1]["name"] as? String, "Chapter 9")
    }

    func testHTMLBridgeQueryAttrFragmentEmptySelector() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)

        // Fragment without wrapping body
        let imgHtml = "<img alt='Test Page' src='https://img-r1.2xstorage.com/0.webp' data-src='https://img-r1.2xstorage.com/data.webp'>"
        context.setObject(imgHtml, forKeyedSubscript: "__imgHtml" as NSString)

        let srcScript = "__yomi_attr(__imgHtml, '', 'src')"
        let srcResult = context.evaluateScript(srcScript)
        XCTAssertEqual(srcResult?.toString(), "https://img-r1.2xstorage.com/0.webp")

        let dataSrcScript = "__yomi_attr(__imgHtml, '', 'data-src')"
        let dataSrcResult = context.evaluateScript(dataSrcScript)
        XCTAssertEqual(dataSrcResult?.toString(), "https://img-r1.2xstorage.com/data.webp")

        // Batch extraction
        let pageHtml = """
        <div class="container-chapter-reader">
            <img src="https://img-r1.2xstorage.com/0.webp">
            <img src="https://img-r1.2xstorage.com/1.webp">
        </div>
        """
        context.setObject(pageHtml, forKeyedSubscript: "__pageHtml" as NSString)
        let attrAllScript = "__yomi_attrAll(__pageHtml, '.container-chapter-reader img', 'src')"
        guard let arrayResult = context.evaluateScript(attrAllScript)?.toArray() as? [String] else {
            XCTFail("attrAll failed")
            return
        }
        XCTAssertEqual(arrayResult.count, 2)
        XCTAssertEqual(arrayResult[0], "https://img-r1.2xstorage.com/0.webp")
        XCTAssertEqual(arrayResult[1], "https://img-r1.2xstorage.com/1.webp")
    }

    func testMangaKakalotSearchListParsing() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }
        HTMLBridge.inject(into: context)
        let pkg = RemoteExtensionPackage(
            id: 2528986671771677900,
            name: "MangaKakalot",
            lang: "en",
            baseUrl: "https://www.mangakakalove.com",
            scriptUrl: ""
        )
        let script = RepoManager.shared.generateScraperScript(for: pkg)
        context.evaluateScript(script)

        let searchHtml = """
        <div id="owl-demo" class="owl-carousel">
            <div class="item"><h3><a href="/manga/carousel-item">Carousel Title</a></h3></div>
        </div>
        <div class="panel_story_list">
            <div class="story_item">
                <a href="https://www.mangakakalove.com/manga/naruto">
                    <img src="https://img-r1.2xstorage.com/thumb/naruto.webp" alt="Naruto">
                </a>
                <div class="story_item_right">
                    <h3 class="story_name"><a href="https://www.mangakakalove.com/manga/naruto">Naruto</a></h3>
                </div>
            </div>
        </div>
        """
        context.setObject(searchHtml, forKeyedSubscript: "__searchHtml" as NSString)
        let parseScript = "Extension.parseSearchList(__searchHtml)"
        guard let result = context.evaluateScript(parseScript), !result.isUndefined, !result.isNull else {
            XCTFail("Extension.parseSearchList returned nil or undefined")
            return
        }
        let dict = result.toDictionary() as? [String: Any]
        let mangas = dict?["mangas"] as? [[String: Any]]
        XCTAssertEqual(mangas?.count, 1)
        XCTAssertEqual(mangas?.first?["title"] as? String, "Naruto")
        XCTAssertEqual(mangas?.first?["url"] as? String, "https://www.mangakakalove.com/manga/naruto")
        XCTAssertEqual(mangas?.first?["thumbnailUrl"] as? String, "https://img-r1.2xstorage.com/thumb/naruto.webp")
    }
}


