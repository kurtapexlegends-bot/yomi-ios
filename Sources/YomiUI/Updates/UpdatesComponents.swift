import SwiftUI
import YomiCore
import YomiDatabase

// MARK: - Section & Filter Models

struct UpdateDateSection {
    let title: String
    let items: [ChapterUpdateItem]
}

public enum UpdateFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case downloaded = "Offline"
    case bookmarked = "Bookmarked"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "bolt.fill"
        case .unread: return "circle.fill"
        case .downloaded: return "arrow.down.circle.fill"
        case .bookmarked: return "bookmark.fill"
        }
    }
}

// MARK: - ChapterUpdateItem Presentation Extensions

extension ChapterUpdateItem {
    var effectiveThumbnailUrl: String? {
        customThumbnailUrl ?? thumbnailUrl
    }

    var displayChapterTitle: String {
        if chapterNumber >= 0 {
            let formatted = chapterNumber.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", chapterNumber)
                : String(format: "%.1f", chapterNumber)
            let trimmed = chapterName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("chapter") || trimmed.lowercased().hasPrefix("ch.") {
                return trimmed.isEmpty ? "Ch. \(formatted)" : trimmed
            }
            return "Ch. \(formatted) — \(trimmed)"
        }
        return chapterName.isEmpty ? "Chapter" : chapterName
    }
}

// MARK: - Row Component

struct UpdateRowView: View {
    let item: ChapterUpdateItem
    let isDownloaded: Bool
    let sourceName: String
    let relativeDate: String
    let onOpenDetail: () -> Void
    let onOpenReader: () -> Void
    let onToggleDownload: () -> Void
    let onToggleRead: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenDetail) {
                YomiCoverImage(
                    urlString: item.effectiveThumbnailUrl,
                    title: item.mangaTitle,
                    cornerRadius: 6
                )
                .frame(width: 44, height: 62)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.mangaTitle)
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.read {
                        Circle()
                            .fill(YomiTheme.unreadBadge)
                            .frame(width: 5, height: 5)
                    }
                    Text(item.displayChapterTitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(item.read ? YomiTheme.textTertiary : YomiTheme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    YomiTag(sourceName, tint: YomiTheme.textTertiary)
                    Text(relativeDate)
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(YomiTheme.success)
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Button(action: onOpenReader) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(YomiTheme.accent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onToggleDownload) {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isDownloaded ? YomiTheme.success : YomiTheme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
        .contextMenu {
            Button(action: onToggleRead) {
                Label(item.read ? "Mark as Unread" : "Mark as Read", systemImage: item.read ? "envelope.badge" : "checkmark.circle")
            }
            Button(action: onToggleDownload) {
                Label(isDownloaded ? "Delete Download" : "Download Chapter", systemImage: isDownloaded ? "trash" : "arrow.down.circle")
            }
            Button(action: onOpenDetail) {
                Label("View Details", systemImage: "info.circle")
            }
        }
    }
}
