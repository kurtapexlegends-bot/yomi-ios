import XCTest
@testable import YomiCore

final class MangaModelTests: XCTestCase {
    func testMangaInitializationAndEffectiveThumbnail() {
        var manga = Manga(
            sourceId: 10001,
            url: "test-url",
            title: "Test Manga",
            thumbnailUrl: "https://example.com/cover.jpg"
        )
        XCTAssertEqual(manga.effectiveThumbnailUrl, "https://example.com/cover.jpg")

        manga.customThumbnailUrl = "https://example.com/custom.jpg"
        XCTAssertEqual(manga.effectiveThumbnailUrl, "https://example.com/custom.jpg")
    }

    func testChapterDisplayTitleFormatting() {
        let chapter = Chapter(
            mangaId: 1,
            url: "ch-1",
            name: "The Beginning",
            chapterNumber: 1.0
        )
        XCTAssertEqual(chapter.displayTitle, "Ch. 1 — The Beginning")

        let fractionalChapter = Chapter(
            mangaId: 1,
            url: "ch-1.5",
            name: "Extra",
            chapterNumber: 1.5
        )
        XCTAssertEqual(fractionalChapter.displayTitle, "Ch. 1.5 — Extra")
    }
}
