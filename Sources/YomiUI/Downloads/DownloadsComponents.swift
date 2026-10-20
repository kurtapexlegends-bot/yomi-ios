import Foundation
import YomiCore

public struct DownloadedGroup: Identifiable {
    public var id: Int64 { manga.id ?? 0 }
    public let manga: Manga
    public let chapters: [DownloadedChapterItem]
    public let byteCount: Int64

    public init(manga: Manga, chapters: [DownloadedChapterItem], byteCount: Int64) {
        self.manga = manga
        self.chapters = chapters
        self.byteCount = byteCount
    }

    public var resumeChapter: Chapter? {
        chapters.first(where: { !$0.chapter.read && $0.chapter.lastPageRead > 0 })?.chapter
            ?? chapters.first(where: { !$0.chapter.read })?.chapter
            ?? chapters.first?.chapter
    }
}

public struct DownloadedChapterItem: Identifiable {
    public var id: Int64 { chapter.id ?? 0 }
    public let chapter: Chapter
    public let byteCount: Int64
    public let fileURL: URL

    public init(chapter: Chapter, byteCount: Int64, fileURL: URL) {
        self.chapter = chapter
        self.byteCount = byteCount
        self.fileURL = fileURL
    }
}
