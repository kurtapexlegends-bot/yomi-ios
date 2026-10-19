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

        let emptyNamedChapter = Chapter(
            mangaId: 1,
            url: "ch-2",
            name: "",
            chapterNumber: 2.0
        )
        XCTAssertEqual(emptyNamedChapter.displayTitle, "Ch. 2")

        let alreadyPrefixedChapter = Chapter(
            mangaId: 1,
            url: "ch-3",
            name: "Chapter 3",
            chapterNumber: 3.0
        )
        XCTAssertEqual(alreadyPrefixedChapter.displayTitle, "Chapter 3")
    }

    func testStableIdUniquenessForUnsavedAndSavedEntities() {
        // Test remote unsaved manga (id is nil)
        let manga1 = Manga(sourceId: 10001, url: "manga-uuid-1", title: "Manga 1")
        let manga2 = Manga(sourceId: 10001, url: "manga-uuid-2", title: "Manga 2")
        XCTAssertNil(manga1.id)
        XCTAssertNil(manga2.id)
        XCTAssertEqual(manga1.stableId, "10001_manga-uuid-1")
        XCTAssertEqual(manga2.stableId, "10001_manga-uuid-2")
        XCTAssertNotEqual(manga1.stableId, manga2.stableId)

        // Test saved manga (id is set)
        var savedManga = manga1
        savedManga.id = 42
        XCTAssertEqual(savedManga.stableId, "db_42")

        // Test chapter stableId
        let ch1 = Chapter(mangaId: 10, url: "chapter-1", name: "Ch 1")
        let ch2 = Chapter(mangaId: 10, url: "chapter-2", name: "Ch 2")
        XCTAssertNil(ch1.id)
        XCTAssertNil(ch2.id)
        XCTAssertEqual(ch1.stableId, "ch_10_chapter-1")
        XCTAssertEqual(ch2.stableId, "ch_10_chapter-2")
        XCTAssertNotEqual(ch1.stableId, ch2.stableId)

        var savedCh = ch1
        savedCh.id = 99
        XCTAssertEqual(savedCh.stableId, "ch_99")
    }
}
