import SwiftUI
import YomiCore

/// Minimalist, high-performance chapter row without redundant card wrappers.
public struct DetailChapterRow: View {
    public let chapter: Chapter
    public let isDownloaded: Bool
    public let onTap: () -> Void
    public let onToggleRead: () -> Void
    public let onToggleBookmark: () -> Void
    public let onDownload: () -> Void

    public init(
        chapter: Chapter,
        isDownloaded: Bool,
        onTap: @escaping () -> Void,
        onToggleRead: @escaping () -> Void,
        onToggleBookmark: @escaping () -> Void,
        onDownload: @escaping () -> Void
    ) {
        self.chapter = chapter
        self.isDownloaded = isDownloaded
        self.onTap = onTap
        self.onToggleRead = onToggleRead
        self.onToggleBookmark = onToggleBookmark
        self.onDownload = onDownload
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chapter.displayTitle)
                            .font(YomiFont.body.weight(chapter.read ? .regular : .semibold))
                            .foregroundStyle(chapter.read ? YomiTheme.textTertiary : YomiTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(relativeDate)
                                .font(YomiFont.micro)
                                .foregroundStyle(YomiTheme.textTertiary)

                            if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                                Text("·")
                                    .font(YomiFont.micro)
                                    .foregroundStyle(YomiTheme.textTertiary)
                                Text(scanlator)
                                    .font(YomiFont.micro)
                                    .foregroundStyle(YomiTheme.textTertiary)
                                    .lineLimit(1)
                            }

                            if chapter.lastPageRead > 0 && !chapter.read {
                                Text("· p.\(chapter.lastPageRead + 1)")
                                    .font(YomiFont.micro)
                                    .foregroundStyle(YomiTheme.accentStrong)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggleBookmark) {
                Image(systemName: chapter.bookmark ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(chapter.bookmark ? YomiTheme.warning : YomiTheme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chapter.bookmark ? "Remove bookmark" : "Bookmark chapter")

            Button(action: isDownloaded ? onTap : onDownload) {
                Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isDownloaded ? YomiTheme.success : YomiTheme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDownloaded ? "Read downloaded chapter" : "Download chapter")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
        .contextMenu {
            Button(action: onToggleRead) {
                Label(
                    chapter.read ? "Mark as Unread" : "Mark as Read",
                    systemImage: chapter.read ? "envelope.badge" : "checkmark.circle"
                )
            }
            Button(action: onToggleBookmark) {
                Label(chapter.bookmark ? "Remove Bookmark" : "Bookmark", systemImage: "bookmark")
            }
            if !isDownloaded {
                Button(action: onDownload) {
                    Label("Download Chapter", systemImage: "arrow.down.circle")
                }
            }
            Button(action: onTap) {
                Label("Read Chapter", systemImage: "book.fill")
            }
        }
    }

    private var relativeDate: String {
        guard chapter.dateUpload > Date(timeIntervalSince1970: 86_400) else {
            return chapter.dateFetch.formatted(date: .abbreviated, time: .omitted)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: chapter.dateUpload, relativeTo: Date())
    }
}

/// Editorial manga header without boxed card borders.
public struct MangaDetailHeroView: View {
    public let manga: Manga
    public let sourceName: String
    public let chapterCount: Int

    public init(manga: Manga, sourceName: String, chapterCount: Int) {
        self.manga = manga
        self.sourceName = sourceName
        self.chapterCount = chapterCount
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            YomiCoverImage(
                urlString: manga.effectiveThumbnailUrl,
                title: manga.title,
                cornerRadius: 8
            )
            .frame(width: 104, height: 146)
            .clipped()
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(manga.title)
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(3)

                if let author = manga.author, !author.isEmpty {
                    Text(author)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    YomiTag(manga.status.title, tint: statusTint)
                    if chapterCount > 0 {
                        YomiTag("\(chapterCount) ch", tint: YomiTheme.accentStrong)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 9, weight: .regular))
                    Text(sourceName)
                        .font(YomiFont.micro)
                        .lineLimit(1)
                }
                .foregroundStyle(YomiTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusTint: Color {
        switch manga.status {
        case .ongoing: return YomiTheme.success
        case .completed, .publishingFinished: return YomiTheme.unreadBadge
        case .cancelled, .licensed: return YomiTheme.danger
        case .onHiatus: return YomiTheme.warning
        case .unknown: return YomiTheme.textSecondary
        }
    }
}

/// Primary and secondary action controls for manga detail.
public struct MangaDetailActionRow: View {
    public let resumeTitle: String
    public let canRead: Bool
    public let isInLibrary: Bool
    public let onResume: () -> Void
    public let onToggleLibrary: () -> Void
    public let onDownloadUnread: () -> Void
    public let onDownloadAll: () -> Void

    public init(
        resumeTitle: String,
        canRead: Bool,
        isInLibrary: Bool,
        onResume: @escaping () -> Void,
        onToggleLibrary: @escaping () -> Void,
        onDownloadUnread: @escaping () -> Void,
        onDownloadAll: @escaping () -> Void
    ) {
        self.resumeTitle = resumeTitle
        self.canRead = canRead
        self.isInLibrary = isInLibrary
        self.onResume = onResume
        self.onToggleLibrary = onToggleLibrary
        self.onDownloadUnread = onDownloadUnread
        self.onDownloadAll = onDownloadAll
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: onResume) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(resumeTitle)
                        .font(YomiFont.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(YomiPrimaryButtonStyle())
            .disabled(!canRead)

            Button(action: onToggleLibrary) {
                Image(systemName: isInLibrary ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isInLibrary ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(YomiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(isInLibrary ? YomiTheme.accent.opacity(0.4) : YomiTheme.border, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onDownloadUnread) {
                    Label("Download Unread", systemImage: "arrow.down.circle")
                }
                Button(action: onDownloadAll) {
                    Label("Download All Chapters", systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(YomiTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(YomiTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(YomiTheme.border, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canRead)
        }
    }
}

public enum MangaChapterFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case bookmarked = "Bookmarked"
    case downloaded = "Offline"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .unread: return "circle.fill"
        case .bookmarked: return "bookmark.fill"
        case .downloaded: return "arrow.down.circle.fill"
        }
    }
}

public enum MangaChapterSort: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"

    public var title: String { rawValue }
}

public struct MangaDetailProgressView: View {
    public let readCount: Int
    public let totalCount: Int
    public let progressFraction: Double

    public init(readCount: Int, totalCount: Int, progressFraction: Double) {
        self.readCount = readCount
        self.totalCount = totalCount
        self.progressFraction = progressFraction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(readCount) of \(totalCount) chapters read")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textSecondary)
                Spacer()
                Text("\(Int(progressFraction * 100))%")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.accentStrong)
            }
            YomiProgressBar(value: progressFraction, tint: YomiTheme.accentStrong, height: 2.5)
        }
        .padding(.top, 2)
    }
}

public struct MangaDetailSynopsisView: View {
    public let description: String
    public let genres: [String]
    @Binding public var isExpanded: Bool

    public init(description: String, genres: [String], isExpanded: Binding<Bool>) {
        self.description = description
        self.genres = genres
        self._isExpanded = isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(description)
                .font(YomiFont.body)
                .foregroundStyle(YomiTheme.textSecondary)
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : 3)

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(isExpanded ? "Less" : "More")
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(YomiTheme.accentStrong)
            }
            .buttonStyle(.plain)

            if !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(genres, id: \.self) { genre in
                            YomiTag(genre, tint: YomiTheme.textTertiary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

public struct MangaChapterFilterBar: View {
    @Binding public var filter: MangaChapterFilter
    @Binding public var sort: MangaChapterSort

    public init(filter: Binding<MangaChapterFilter>, sort: Binding<MangaChapterSort>) {
        self._filter = filter
        self._sort = sort
    }

    public var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MangaChapterFilter.allCases, id: \.self) { option in
                        YomiFilterChip(
                            title: option.title,
                            isSelected: filter == option,
                            icon: nil
                        ) {
                            filter = option
                        }
                    }
                }
            }

            Menu {
                ForEach(MangaChapterSort.allCases, id: \.self) { option in
                    Button {
                        sort = option
                    } label: {
                        if sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(YomiTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(YomiTheme.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(YomiTheme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }
}
