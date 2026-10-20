import SwiftUI
import YomiCore

/// Dense chapter row used by the manga detail screen.
struct DetailChapterRow: View {
    let chapter: Chapter
    let isDownloaded: Bool
    let onTap: () -> Void
    let onToggleRead: () -> Void
    let onToggleBookmark: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onTap) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(chapter.read ? YomiTheme.surface : YomiTheme.accentSoft)
                            .frame(width: 34, height: 34)
                        if chapter.read {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(YomiTheme.success)
                        } else {
                            Text(chapterNumberLabel)
                                .font(YomiFont.micro)
                                .foregroundStyle(YomiTheme.accentStrong)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(chapter.displayTitle)
                            .font(YomiFont.body.weight(chapter.read ? .regular : .semibold))
                            .foregroundStyle(chapter.read ? YomiTheme.textSecondary : YomiTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 7) {
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(chapter.bookmark ? YomiTheme.warning : YomiTheme.textTertiary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chapter.bookmark ? "Remove bookmark" : "Bookmark chapter")

            Button(action: isDownloaded ? onTap : onDownload) {
                Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isDownloaded ? YomiTheme.success : YomiTheme.textTertiary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDownloaded ? "Read downloaded chapter" : "Download chapter")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(chapter.bookmark ? YomiTheme.warning.opacity(0.32) : YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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

    private var chapterNumberLabel: String {
        if chapter.chapterNumber >= 0 {
            let value = chapter.chapterNumber.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", chapter.chapterNumber)
                : String(format: "%.1f", chapter.chapterNumber)
            return value
        }
        return "•"
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

enum MangaChapterFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case bookmarked = "Bookmarked"
    case downloaded = "Offline"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .unread: return "circle.fill"
        case .bookmarked: return "bookmark.fill"
        case .downloaded: return "arrow.down.circle.fill"
        }
    }
}

enum MangaChapterSort: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"

    var title: String { rawValue }
}
