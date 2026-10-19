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
}
