import Foundation
import ZIPFoundation
import YomiCore

/// Packages downloaded chapter images and ComicInfo.xml metadata into standard .cbz zip archives.
public enum CBZArchiver {
    
    /// Creates a .cbz archive at destinationURL containing image pages and metadata.
    public static func createCBZ(
        at destinationURL: URL,
        manga: Manga,
        chapter: Chapter,
        pageDataList: [Data]
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        guard let archive = Archive(url: destinationURL, accessMode: .create) else {
            throw YomiError.storageError("Failed to initialize CBZ archive at \(destinationURL.path)")
        }

        // Generate ComicInfo.xml
        let comicInfoXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <Title>\(escapeXML(chapter.name))</Title>
            <Series>\(escapeXML(manga.title))</Series>
            <Number>\(chapter.chapterNumber)</Number>
            <Writer>\(escapeXML(manga.author ?? ""))</Writer>
            <Penciller>\(escapeXML(manga.artist ?? ""))</Penciller>
            <Summary>\(escapeXML(manga.description ?? ""))</Summary>
            <PageCount>\(pageDataList.count)</PageCount>
        </ComicInfo>
        """

        if let xmlData = comicInfoXML.data(using: .utf8) {
            try archive.addEntry(with: "ComicInfo.xml", type: .file, uncompressedSize: Int64(xmlData.count), compressionMethod: .deflate) { position, size in
                xmlData.subdata(in: Int(position)..<Int(position + size))
            }
        }

        // Add page image files
        for (index, data) in pageDataList.enumerated() {
            let fileName = String(format: "%03d.jpg", index)
            try archive.addEntry(with: fileName, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .none) { position, size in
                data.subdata(in: Int(position)..<Int(position + size))
            }
        }
    }

    /// Reads all page image entries from an existing .cbz archive in alphabetical order.
    public static func readCBZPages(from archiveURL: URL) throws -> [ReaderPage] {
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            throw YomiError.storageError("Failed to open CBZ archive at \(archiveURL.path)")
        }

        let imageEntries = archive.filter { entry in
            let ext = (entry.path as NSString).pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "webp", "gif"].contains(ext)
        }.sorted { $0.path < $1.path }

        return imageEntries.enumerated().map { index, entry in
            ReaderPage(
                index: index,
                url: "\(archiveURL.path)#\(entry.path)",
                imageUrl: "\(archiveURL.path)#\(entry.path)",
                localPath: archiveURL.path
            )
        }
    }

    /// Extracts raw image data for a specific entry path inside a .cbz archive.
    public static func extractData(from archiveURL: URL, entryPath: String) throws -> Data {
        guard let archive = Archive(url: archiveURL, accessMode: .read),
              let entry = archive[entryPath] else {
            throw YomiError.storageError("Entry not found in CBZ: \(entryPath)")
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private static func escapeXML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
