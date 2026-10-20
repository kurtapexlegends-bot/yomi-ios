import SwiftUI
import YomiCore
import YomiDatabase

/// Grid card used by the library, source browsing, and search results.
public struct MangaGridCard: View {
    public let manga: Manga
    public let unreadCount: Int
    public let progress: Double
    public let showsLibraryBadge: Bool

    public init(
        manga: Manga,
        unreadCount: Int = 0,
        progress: Double = 0,
        showsLibraryBadge: Bool = true
    ) {
        self.manga = manga
        self.unreadCount = unreadCount
        self.progress = progress
        self.showsLibraryBadge = showsLibraryBadge
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                YomiCoverImage(
                    urlString: manga.effectiveThumbnailUrl,
                    title: manga.title,
                    cornerRadius: YomiTheme.cornerRadiusMedium
                )
                .aspectRatio(11.0 / 16.0, contentMode: .fit)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
                .allowsHitTesting(false)

                if showsLibraryBadge && manga.inLibrary {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(YomiTheme.accent.opacity(0.92))
                        .clipShape(Circle())
                        .padding(7)
                }

                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(YomiFont.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(YomiTheme.accent)
                        .clipShape(Capsule())
                        .padding(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(manga.title)
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(9)
            }
            .overlay(alignment: .bottom) {
                if progress > 0 && progress < 1 {
                    YomiProgressBar(value: progress, tint: YomiTheme.accentStrong, height: 2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
            }

            if let author = manga.author, !author.isEmpty {
                Text(author)
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 7)
                    .padding(.horizontal, 2)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Dense list row used when the library is switched to list mode.
public struct MangaListRow: View {
    public let manga: Manga
    public let unreadCount: Int
    public let progress: Double

    public init(manga: Manga, unreadCount: Int = 0, progress: Double = 0) {
        self.manga = manga
        self.unreadCount = unreadCount
        self.progress = progress
    }

    public var body: some View {
        HStack(spacing: 14) {
            YomiCoverImage(
                urlString: manga.effectiveThumbnailUrl,
                title: manga.title,
                cornerRadius: 10
            )
            .frame(width: 62, height: 90)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(manga.title)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(YomiFont.micro)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(YomiTheme.accent)
                            .clipShape(Capsule())
                    }
                }

                if let author = manga.author, !author.isEmpty {
                    Text(author)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    YomiTag(manga.status.title, tint: statusTint)
                    if manga.inLibrary {
                        YomiTag("IN LIBRARY", tint: YomiTheme.accentStrong)
                    }
                }

                if progress > 0 {
                    HStack(spacing: 8) {
                        YomiProgressBar(value: progress, tint: YomiTheme.accentStrong, height: 3)
                        Text("\(Int(progress * 100))%")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .padding(12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        .contentShape(Rectangle())
    }

    private var statusTint: Color {
        switch manga.status {
        case .completed, .publishingFinished:
            return YomiTheme.success
        case .ongoing:
            return YomiTheme.unreadBadge
        case .onHiatus, .cancelled:
            return YomiTheme.warning
        default:
            return YomiTheme.textSecondary
        }
    }
}

/// Backwards-compatible card used by source exploration.
public struct MangaCardView: View {
    public let manga: Manga
    public var onToggleLibrary: (() -> Void)?

    public init(manga: Manga, onToggleLibrary: (() -> Void)? = nil) {
        self.manga = manga
        self.onToggleLibrary = onToggleLibrary
    }

    public var body: some View {
        MangaGridCard(manga: manga)
            .contextMenu {
                if manga.inLibrary {
                    Button(role: .destructive) {
                        Task {
                            if let id = manga.id {
                                try? await MangaRepository().setInLibrary(mangaId: id, inLibrary: false)
                                onToggleLibrary?()
                            }
                        }
                    } label: {
                        Label("Remove from Library", systemImage: "trash")
                    }
                } else {
                    Button {
                        Task {
                            let saved = (try? await MangaRepository().upsert(manga)) ?? manga
                            if let id = saved.id {
                                try? await MangaRepository().setInLibrary(mangaId: id, inLibrary: true)
                                onToggleLibrary?()
                            }
                        }
                    } label: {
                        Label("Add to Library", systemImage: "heart")
                    }
                }
            }
    }
}
