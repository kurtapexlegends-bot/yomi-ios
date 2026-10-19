import XCTest
@testable import YomiDownload
@testable import YomiCore

final class LocalCBZSourceTests: XCTestCase {

    private func makeTempArchiveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("yomi-cbz-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("chapter.cbz")
    }

    func testReadCBZPagesExposesArchiveEntriesInsteadOfWholeArchive() throws {
        let archiveURL = makeTempArchiveURL()
        try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let pageBytes: [Data] = [Data("page-one".utf8), Data("page-two".utf8), Data("page-three".utf8)]
        let chapter = Chapter(mangaId: 1, url: "/chapter/1", name: "Chapter 1")
        let manga = Manga(sourceId: 1, url: "/manga/1", title: "Test Manga")

        try CBZArchiver.createCBZ(at: archiveURL, manga: manga, chapter: chapter, pageDataList: pageBytes)

        let pages = try CBZArchiver.readCBZPages(from: archiveURL)
        XCTAssertEqual(pages.count, pageBytes.count)

        // Previously localPath pointed at the .cbz itself, so the reader loaded the whole
        // archive into memory per page (out-of-memory crash) and never decoded an image.
        for page in pages {
            XCTAssertNil(page.localPath, "CBZ pages must not be treated as standalone image files")
            XCTAssertNotNil(page.archiveEntry)
            XCTAssertTrue(page.url.contains("#"), "CBZ page URLs should reference their archive entry")
        }
    }

    func testLocalCBZSourceExtractsExactPageData() throws {
        let archiveURL = makeTempArchiveURL()
        try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let pageBytes: [Data] = [Data(repeating: 0x41, count: 2048), Data(repeating: 0x42, count: 4096)]
        let chapter = Chapter(mangaId: 1, url: "/chapter/2", name: "Chapter 2")
        let manga = Manga(sourceId: 1, url: "/manga/2", title: "Test Manga 2")

        try CBZArchiver.createCBZ(at: archiveURL, manga: manga, chapter: chapter, pageDataList: pageBytes)

        let source = try LocalCBZSource(archiveURL: archiveURL)
        XCTAssertEqual(source.pages.count, 2)

        let firstPage = try XCTUnwrap(source.pages.first)
        let data = try source.getImageData(page: firstPage)
        XCTAssertEqual(data, pageBytes[0])
        XCTAssertLessThan(data.count, 16 * 1024, "Only the single entry should be extracted")
    }
}
