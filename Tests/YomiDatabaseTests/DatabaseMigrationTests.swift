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
}
