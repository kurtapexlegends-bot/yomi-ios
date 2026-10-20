import SwiftUI
import YomiCore
import YomiDatabase

/// Minimalist, cover-first grid card for library, source browsing, and search results.
/// Cover art is kept pristine without heavy gradients or superimposed text.
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
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                YomiCoverImage(
                    urlString: manga.effectiveThumbnailUrl,
                    title: manga.title,
                    cornerRadius: 8
                )
                .aspectRatio(3.0 / 4.2, contentMode: .fit)

                // Top-left: Library indicator
                if showsLibraryBadge && manga.inLibrary {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(YomiTheme.accentStrong)
                            .padding(5)
                            .background(Color.black.opacity(0.72))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(YomiTheme.border, lineWidth: 0.5))
                            .padding(6)
                        Spacer()
                    }
                }

                // Top-right: Unread badge
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(YomiFont.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(YomiTheme.accent)
                        .clipShape(Capsule())
                        .padding(6)
                }

                // Bottom edge: Reading progress line
                if progress > 0 && progress < 1 {
                    VStack {
                        Spacer()
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.5))
                                Rectangle()
                                    .fill(YomiTheme.accentStrong)
                                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * progress)))
                            }
                        }
                        .frame(height: 2.5)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                    }
                }
            }

            // Title below cover
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title)
                    .font(YomiFont.caption.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let author = manga.author, !author.isEmpty {
                    Text(author)
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 1)
        }
        .contentShape(Rectangle())
    }
}

/// Minimalist list row with clear information density and zero clunky border soup.
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
        HStack(spacing: 12) {
            YomiCoverImage(
                urlString: manga.effectiveThumbnailUrl,
                title: manga.title,
                cornerRadius: 6
            )
            .frame(width: 52, height: 74)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
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
                            .padding(.vertical, 2.5)
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
                        YomiProgressBar(value: progress, tint: YomiTheme.accentStrong, height: 2)
                        Text("\(Int(progress * 100))%")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
