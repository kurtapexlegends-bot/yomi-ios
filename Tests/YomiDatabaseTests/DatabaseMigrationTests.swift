import XCTest
import GRDB
@testable import YomiCore
@testable import YomiDatabase

final class DatabaseMigrationTests: XCTestCase {
    var dbManager: DatabaseManager!
    var mangaRepo: MangaRepository!

    override func setUpWithError() throws {
        dbManager = try DatabaseManager.makeInMemory()
        mangaRepo = MangaRepository(dbManager: dbManager)
    }

    func testDatabaseInsertionAndFTS5Search() async throws {
        let manga = Manga(
            sourceId: 10001,
            url: "berserk",
            title: "Berserk",
            author: "Kentarou Miura",
            artist: "Kentarou Miura",
            description: "Guts, known as the Black Swordsman, seeks sanctuary from the demonic forces pursuing him.",
            inLibrary: true
        )

        let saved = try await mangaRepo.upsert(manga)
        XCTAssertNotNil(saved.id)

        // Test FTS5 instant search across title and author
        let searchResults = try await mangaRepo.searchFTS(query: "Miura")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.title, "Berserk")

        let titleResults = try await mangaRepo.searchFTS(query: "Berserk")
        XCTAssertEqual(titleResults.count, 1)
    }

    func testHistoryRepositoryOperations() async throws {
        let chapterRepo = ChapterRepository(dbManager: dbManager)
        let historyRepo = HistoryRepository(dbManager: dbManager)

        let manga = Manga(sourceId: 10001, url: "test-manga", title: "Test Manga", inLibrary: true)
        let savedManga = try await mangaRepo.upsert(manga)
        guard let mangaId = savedManga.id else {
            XCTFail("Failed to get manga id")
            return
        }

        let chapter1 = Chapter(mangaId: mangaId, url: "ch-1", name: "Chapter 1", chapterNumber: 1.0)
        let chapter2 = Chapter(mangaId: mangaId, url: "ch-2", name: "Chapter 2", chapterNumber: 2.0)
        let savedChapters = try await chapterRepo.syncChapters([chapter1, chapter2], forMangaId: mangaId)
        guard let ch1Id = savedChapters[0].id, let ch2Id = savedChapters[1].id else {
            XCTFail("Failed to get chapter ids")
            return
        }

        // Test logging progress to history
        try await chapterRepo.updateProgress(chapterId: ch1Id, lastPageRead: 14, isRead: false)
        try await chapterRepo.updateProgress(chapterId: ch2Id, lastPageRead: 25, isRead: true)

        // Test updating progress with logHistory = false does not insert into history
        let chapter3 = Chapter(mangaId: mangaId, url: "ch-3", name: "Chapter 3", chapterNumber: 3.0)
        let savedCh3 = try await chapterRepo.syncChapters([chapter3], forMangaId: mangaId)
        let ch3Id = savedCh3[0].id!
        try await chapterRepo.updateProgress(chapterId: ch3Id, lastPageRead: 0, isRead: true, logHistory: false)

        let history = try await historyRepo.getHistory(limit: 10)
        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history.contains(where: { $0.chapterId == ch3Id }))
        XCTAssertEqual(history[0].chapterId, ch2Id) // latest first
        XCTAssertEqual(history[0].mangaTitle, "Test Manga")
        XCTAssertTrue(history[0].isRead)
        XCTAssertEqual(history[1].chapterId, ch1Id)
        XCTAssertEqual(history[1].lastPageRead, 14)
        XCTAssertFalse(history[1].isRead)

        // Test delete single history item
        try await historyRepo.deleteHistoryItem(id: history[0].id)
        let afterDelete = try await historyRepo.getHistory(limit: 10)
        XCTAssertEqual(afterDelete.count, 1)
        XCTAssertEqual(afterDelete[0].chapterId, ch1Id)

        // Test clear all history
        try await historyRepo.clearAllHistory()
        let afterClear = try await historyRepo.getHistory(limit: 10)
        XCTAssertEqual(afterClear.count, 0)
    }

    func testRecentUpdatesQueryFiltersLibraryOnly() async throws {
        let chapterRepo = ChapterRepository(dbManager: dbManager)

        // Manga in library
        let libManga = Manga(sourceId: 10001, url: "in-lib", title: "In Library", inLibrary: true)
        let savedLib = try await mangaRepo.upsert(libManga)
        let libMangaId = savedLib.id!

        // Manga NOT in library
        let notLibManga = Manga(sourceId: 10001, url: "not-in-lib", title: "Not In Library", inLibrary: false)
        let savedNotLib = try await mangaRepo.upsert(notLibManga)
        let notLibMangaId = savedNotLib.id!

        let chLib = Chapter(mangaId: libMangaId, url: "ch-lib-1", name: "Lib Chapter 1", chapterNumber: 1.0)
        let chNotLib = Chapter(mangaId: notLibMangaId, url: "ch-notlib-1", name: "NotLib Chapter 1", chapterNumber: 1.0)

        _ = try await chapterRepo.syncChapters([chLib], forMangaId: libMangaId)
        _ = try await chapterRepo.syncChapters([chNotLib], forMangaId: notLibMangaId)

        let updates = try await chapterRepo.getRecentUpdates(limit: 10)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.mangaTitle, "In Library")
        XCTAssertEqual(updates.first?.chapterName, "Lib Chapter 1")
    }

    func testKeiyoushiRepoSeededOnMigration() async throws {
        let repoRepo = ExtensionRepoRepository(dbManager: dbManager)
        let repos = try await repoRepo.getAllRepos()
        XCTAssertFalse(repos.isEmpty)
        XCTAssertTrue(repos.contains(where: { $0.name == "Keiyoushi" }))
        XCTAssertTrue(repos.contains(where: { $0.url.contains("keiyoushi") }))
    }

    func testChapterDeduplicationOnSync() async throws {
        let chapterRepo = ChapterRepository(dbManager: dbManager)
        let manga = Manga(sourceId: 10001, url: "dedup-manga", title: "Dedup Manga", inLibrary: true)
        let savedManga = try await mangaRepo.upsert(manga)
        let mangaId = savedManga.id!

        // Two chapters with identical URLs (common scraper bug / source anomaly)
        let duplicate1 = Chapter(mangaId: mangaId, url: "duplicate-ch-url", name: "Chapter 1", chapterNumber: 1.0)
        let duplicate2 = Chapter(mangaId: mangaId, url: "duplicate-ch-url", name: "Chapter 1 Duplicate", chapterNumber: 1.0)

        let savedChapters = try await chapterRepo.syncChapters([duplicate1, duplicate2], forMangaId: mangaId)
        XCTAssertEqual(savedChapters.count, 1)
        XCTAssertEqual(savedChapters.first?.name, "Chapter 1")
    }
}
