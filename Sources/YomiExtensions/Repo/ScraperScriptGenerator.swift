import Foundation
import YomiCore

/// Generates compliant JavaScriptCore scraper scripts for community repository extensions.
enum ScraperScriptGenerator {
    
    static func generateScraperScript(for package: RemoteExtensionPackage) -> String {
        let pkgLower = package.packageName?.lowercased() ?? ""
        let nameLower = package.name.lowercased()
        let baseLower = package.baseUrl.lowercased()

        var baseUrl = package.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while baseUrl.hasSuffix("/") { baseUrl.removeLast() }

        // 1. MangaKakalot / Manganato archetype
        let isMangakakalot = baseLower.contains("mangakakalot") ||
                             baseLower.contains("mangakakalove") ||
                             nameLower.contains("mangakakalot") ||
                             pkgLower.contains("mangakakalot") ||
                             baseLower.contains("manganato") ||
                             pkgLower.contains("manganato")
        if isMangakakalot {
            return MangaKakalotScraper.generateScript(baseUrl: "https://www.mangakakalove.com")
        }

        // 2. MangaKatana archetype
        let isMangaKatana = baseLower.contains("mangakatana") ||
                            nameLower.contains("mangakatana") ||
                            pkgLower.contains("mangakatana")
        if isMangaKatana {
            return MangaKatanaScraper.generateScript(baseUrl: "https://mangakatana.com")
        }

        // 3. Madara / Scanlator / WordPress archetype (Asura, Flame, Reaper, ManhwaClan, etc.)
        let isMadara = baseLower.contains("asura") ||
                       nameLower.contains("asura") ||
                       pkgLower.contains("asura") ||
                       baseLower.contains("flame") ||
                       nameLower.contains("flame") ||
                       pkgLower.contains("flame") ||
                       baseLower.contains("reaper") ||
                       nameLower.contains("reaper") ||
                       pkgLower.contains("reaper") ||
                       baseLower.contains("manhwa") ||
                       pkgLower.contains("manhwa") ||
                       baseLower.contains("madara") ||
                       pkgLower.contains("madara") ||
                       baseLower.contains("clan") ||
                       baseLower.contains("scans")

        if isMadara {
            if baseUrl.isEmpty { baseUrl = "https://asurascans.com" }
            return MadaraScraper.generateScript(baseUrl: baseUrl)
        }

        // 4. Smart Universal HTML Engine
        if baseUrl.isEmpty { baseUrl = "https://mangapill.com" }
        return UniversalScraper.generateScript(baseUrl: baseUrl)
    }
}
