import Foundation
import ZIPFoundation
import YomiCore

/// Handles importing local .cbz, .zip, and comic files from the iOS Files app or AirDrop.
public enum LocalComicImporter {
    public static let localSourceId: Int64 = 0

    /// Imports an external comic archive into Yomi's local storage sandbox.
    public static func importArchive(from sourceURL: URL) throws -> (Manga, Chapter) {
        let fileManager = FileManager.default

        // Request security-scoped access if needed
        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let localDir = appSupport.appendingPathComponent("Yomi/local_comics", isDirectory: true)
        if !fileManager.fileExists(atPath: localDir.path) {
            try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        }

        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let destinationURL = localDir.appendingPathComponent("\(UUID().uuidString).cbz")
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        // Parse ComicInfo.xml or fallback to filename
        let pages = try CBZArchiver.readCBZPages(from: destinationURL)
        guard !pages.isEmpty else {
            throw YomiError.storageError("Archive contains no readable image files")
        }

        var mangaTitle = fileName
        var chapterName = "Chapter 1"
        var chapterNumber: Float = 1.0
        var author: String?
        var artist: String?
        var desc: String?

        // Try extracting ComicInfo.xml
        if let xmlData = try? CBZArchiver.extractData(from: destinationURL, entryPath: "ComicInfo.xml"),
           let xmlString = String(data: xmlData, encoding: .utf8) {
            if let series = extractXMLTag(from: xmlString, tag: "Series") { mangaTitle = series }
            if let numStr = extractXMLTag(from: xmlString, tag: "Number"), let num = Float(numStr) { chapterNumber = num }
            if let title = extractXMLTag(from: xmlString, tag: "Title") { chapterName = title }
            author = extractXMLTag(from: xmlString, tag: "Writer")
            artist = extractXMLTag(from: xmlString, tag: "Penciller")
            desc = extractXMLTag(from: xmlString, tag: "Summary")
        }

        // Extract first page as cover
        var coverPath: String?
        if let firstPage = pages.first,
           let entryPath = firstPage.url.components(separatedBy: "#").last,
           let coverData = try? CBZArchiver.extractData(from: destinationURL, entryPath: entryPath) {
            let coverURL = localDir.appendingPathComponent("\(UUID().uuidString)_cover.jpg")
            try? coverData.write(to: coverURL)
            coverPath = coverURL.path
        }

        let manga = Manga(
            sourceId: localSourceId,
            url: destinationURL.path,
            title: mangaTitle,
            author: author,
            artist: artist,
            description: desc,
            genres: ["Local"],
            status: .completed,
            thumbnailUrl: coverPath,
            customThumbnailUrl: coverPath,
            inLibrary: true
        )

        let chapter = Chapter(
            mangaId: 0,
            url: destinationURL.path,
            name: chapterName,
            chapterNumber: chapterNumber,
            sourceOrder: 0
        )

        return (manga, chapter)
    }

    private static func extractXMLTag(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
        let nsString = xml as NSString
        guard let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsString.length)) else { return nil }
        return nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
