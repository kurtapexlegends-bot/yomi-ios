import SwiftUI
import YomiCore
import YomiDatabase
import YomiSync

/// Tracker linking and progress synchronization sheet (AniList, MyAnimeList).
struct MangaTrackingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let manga: Manga
    let onChanged: () -> Void

    @State private var tracks: [Track] = []
    @State private var results: [TrackerSearchResult] = []
    @State private var query: String = ""
    @State private var isSearching: Bool = false
    @State private var isLoading: Bool = true
    @State private var linkingId: Int64?
    @State private var syncingTrackId: Int64?
    @State private var errorMessage: String?

    private let trackRepo = TrackRepository()
    private let chapterRepo = ChapterRepository()
    private let aniList = AniListClient.shared

    var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !aniList.isLoggedIn {
                            loginBanner
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.danger)
                        }

                        if isLoading {
                            ProgressView().tint(YomiTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 24)
                        } else if !tracks.isEmpty {
                            linkedSection
                        }

                        searchSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Tracking")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .task {
                query = manga.title
                await loadTracks()
                if aniList.isLoggedIn {
                    search()
                }
            }
        }
    }

    private var loginBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(YomiTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("AniList is not connected")
                    .font(YomiFont.caption.weight(.bold))
                    .foregroundStyle(YomiTheme.textPrimary)
                Text("Connect AniList in Settings → Tracking to search for this title, link it, and sync reading progress.")
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(YomiTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var linkedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            YomiSectionHeader("Linked Tracks", subtitle: "\(tracks.count) service(s)")

            VStack(spacing: 8) {
                ForEach(tracks) { track in
                    linkedRow(track)
                }
            }
        }
    }

    private func linkedRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YomiTheme.accentStrong)
                .frame(width: 38, height: 38)
                .background(YomiTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(serviceName(track.syncId))
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                HStack(spacing: 6) {
                    YomiTag(track.status.title, tint: YomiTheme.success)
                    Text("Ch. \(Int(track.lastChapterRead))")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                    if track.totalChapters > 0 {
                        Text("/ \(track.totalChapters)")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.textTertiary)
                    }
                }
            }

            Spacer()

            Menu {
                ForEach(TrackStatus.allCases, id: \.self) { status in
                    Button(status.title) {
                        updateStatus(track, status: status)
                    }
                }
                Divider()
                Button {
                    sync(track)
                } label: {
                    Label("Sync Progress", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) {
                    remove(track)
                } label: {
                    Label("Remove Link", systemImage: "trash")
                }
            } label: {
                if syncingTrackId == track.id {
                    ProgressView().tint(YomiTheme.textSecondary).scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YomiTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader("Link on AniList", subtitle: "Search for this title")

            YomiSearchField(
                text: $query,
                placeholder: "Search AniList",
                onSubmit: { search() }
            )

            if isSearching {
                ProgressView().tint(YomiTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if !results.isEmpty {
                VStack(spacing: 8) {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                }
            } else {
                Text(aniList.isLoggedIn ? "Search to link this title to AniList." : "Connect AniList to search and link titles.")
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textTertiary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func resultRow(_ result: TrackerSearchResult) -> some View {
        HStack(spacing: 11) {
            YomiCoverImage(urlString: result.coverUrl, title: result.title, cornerRadius: 8)
                .frame(width: 42, height: 60)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(2)
                if result.totalChapters > 0 {
                    Text("\(result.totalChapters) chapters")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                }
            }

            Spacer(minLength: 4)

            Button {
                link(result)
            } label: {
                if linkingId == result.id {
                    ProgressView().tint(.white).scaleEffect(0.6)
                } else {
                    Text("Link")
                }
            }
            .buttonStyle(YomiPrimaryButtonStyle())
            .disabled(aniList.isLoggedIn == false || linkingId != nil || manga.id == nil)
        }
        .padding(10)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func loadTracks() async {
        guard let mangaId = manga.id else {
            isLoading = false
            return
        }
        isLoading = true
        tracks = (try? await trackRepo.getTracks(forMangaId: mangaId)) ?? []
        isLoading = false
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil

        Task {
            do {
                results = try await aniList.searchManga(query: trimmed)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func link(_ result: TrackerSearchResult) {
        guard let mangaId = manga.id else { return }
        linkingId = result.id

        Task {
            do {
                let progress = await localChapterProgress()
                let track = Track(
                    mangaId: mangaId,
                    syncId: TrackerServiceType.aniList.rawValue,
                    remoteId: result.id,
                    title: result.title,
                    lastChapterRead: progress,
                    totalChapters: result.totalChapters,
                    score: 0,
                    status: .reading,
                    trackingUrl: result.trackingUrl
                )
                _ = try await trackRepo.upsertTrack(track)
                await loadTracks()
                onChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
            linkingId = nil
        }
    }

    private func updateStatus(_ track: Track, status: TrackStatus) {
        Task {
            let progress = max(track.lastChapterRead, await localChapterProgress())
            do {
                if aniList.isLoggedIn {
                    try await aniList.updateProgress(
                        mediaId: track.remoteId,
                        chapterProgress: Int(progress),
                        status: status,
                        score: track.score
                    )
                }
                var updated = track
                updated.status = status
                updated.lastChapterRead = progress
                _ = try? await trackRepo.upsertTrack(updated)
                await loadTracks()
                onChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sync(_ track: Track) {
        syncingTrackId = track.id
        Task {
            do {
                let progress = max(track.lastChapterRead, await localChapterProgress())
                try await aniList.updateProgress(
                    mediaId: track.remoteId,
                    chapterProgress: Int(progress),
                    status: track.status,
                    score: track.score
                )
                var updated = track
                updated.lastChapterRead = progress
                _ = try? await trackRepo.upsertTrack(updated)
                await loadTracks()
            } catch {
                errorMessage = error.localizedDescription
            }
            syncingTrackId = nil
        }
    }

    /// Highest locally completed chapter, used when linking and when manually pushing progress.
    private func localChapterProgress() async -> Float {
        guard let mangaId = manga.id,
              let chapters = try? await chapterRepo.getChapters(forMangaId: mangaId) else {
            return 0
        }
        return chapters.filter(\.read).map(\.chapterNumber).max() ?? 0
    }

    private func remove(_ track: Track) {
        guard let id = track.id else { return }
        Task {
            try? await trackRepo.deleteTrack(id: id)
            await loadTracks()
            onChanged()
        }
    }

    private func serviceName(_ syncId: Int) -> String {
        TrackerServiceType(rawValue: syncId)?.displayName ?? "Tracker"
    }
}
