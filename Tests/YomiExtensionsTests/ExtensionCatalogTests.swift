import XCTest
@testable import YomiExtensions
@testable import YomiCore

final class ExtensionCatalogTests: XCTestCase {

    private func makePackage(
        id: Int64,
        name: String,
        lang: String,
        packageName: String?,
        baseUrl: String = "https://akuma.moe"
    ) -> RemoteExtensionPackage {
        RemoteExtensionPackage(
            id: id,
            name: name,
            lang: lang,
            baseUrl: baseUrl,
            version: "1.6.10",
            scriptUrl: "https://example.com/ext.apk",
            packageName: packageName
        )
    }

    func testAkumaLanguageVariantsCollapseIntoOneGroup() throws {
        let languages = ["all", "en", "id", "jv", "ca", "cs", "da", "de", "es", "fr", "it", "hi", "hu", "nl", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh", "ar", "bg", "el", "fi", "ko"]
        let packages = languages.enumerated().map { index, lang in
            makePackage(
                id: Int64(index + 1),
                name: "Akuma",
                lang: lang,
                packageName: "eu.kanade.tachiyomi.extension.all.akuma"
            )
        }

        let groups = ExtensionCatalog.group(packages)

        XCTAssertEqual(groups.count, 1, "All 27 language variants must collapse into a single row")
        let akuma = try XCTUnwrap(groups.first)
        XCTAssertEqual(akuma.variants.count, languages.count)
        XCTAssertEqual(akuma.name, "Akuma")
        XCTAssertEqual(akuma.defaultLanguage, "en", "English must be the default install language")
        XCTAssertEqual(akuma.variants.first?.lang, "en")
        XCTAssertEqual(akuma.variants.dropFirst().first?.lang, "all", "'all' should be the second variant")
    }

    func testLanguageSpecificPackageNamesCollapseIntoOneGroup() throws {
        let packages = [
            makePackage(id: 1, name: "MangaKakalot", lang: "en", packageName: "eu.kanade.tachiyomi.extension.en.mangakakalot"),
            makePackage(id: 2, name: "MangaKakalot", lang: "all", packageName: "eu.kanade.tachiyomi.extension.all.mangakakalot"),
            makePackage(id: 3, name: "MangaKakalot", lang: "es", packageName: "eu.kanade.tachiyomi.extension.es.mangakakalot")
        ]

        let groups = ExtensionCatalog.group(packages)

        XCTAssertEqual(groups.count, 1, "Language-specific APKs must share one store row")
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.variantCount, 3)
        XCTAssertEqual(group.variants.map(\.lang), ["en", "all", "es"])
    }

    func testDifferentExtensionsRemainSeparateGroups() {
        let packages = [
            makePackage(id: 1, name: "Akuma", lang: "en", packageName: "pkg.akuma"),
            makePackage(id: 2, name: "Akuma", lang: "es", packageName: "pkg.akuma"),
            makePackage(id: 3, name: "MangaKakalot", lang: "en", packageName: "pkg.mangakakalot", baseUrl: "https://www.mangakakalot.gg")
        ]

        let groups = ExtensionCatalog.group(packages)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.name), ["Akuma", "MangaKakalot"], "Groups must be sorted alphabetically")
    }

    func testMissingPackageNameFallsBackToDisplayName() {
        let packages = [
            makePackage(id: 1, name: "Some Source", lang: "en", packageName: nil),
            makePackage(id: 2, name: "Some Source", lang: "fr", packageName: nil)
        ]

        let groups = ExtensionCatalog.group(packages)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.variants.count, 2)
    }

    func testVariantSortingIsDeterministic() {
        let sorted = ExtensionCatalog.sortVariants([
            makePackage(id: 1, name: "X", lang: "ru", packageName: "pkg.x"),
            makePackage(id: 2, name: "X", lang: "all", packageName: "pkg.x"),
            makePackage(id: 3, name: "X", lang: "en", packageName: "pkg.x"),
            makePackage(id: 4, name: "X", lang: "de", packageName: "pkg.x")
        ])
        XCTAssertEqual(sorted.map(\.lang), ["en", "all", "de", "ru"])
    }
}
