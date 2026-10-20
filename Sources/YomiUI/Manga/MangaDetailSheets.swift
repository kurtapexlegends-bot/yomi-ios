import SwiftUI
import YomiCore
import YomiDatabase
import YomiSync

/// Category assignment sheet with biometric protection for locked shelves.
struct MangaCategorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let mangaId: Int64
    let onSaved: () -> Void

    @State private var categories: [YomiCategory] = []
    @State private var selectedIds: Set<Int64> = []
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var newCategoryName: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    private let categoryRepo = CategoryRepository()
    private let privacyManager = PrivacyManager.shared
    private let biometrics = BiometricSecurityManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        YomiCard(padding: 13) {
                            Text("Choose the shelves this title belongs to. Locked categories require authentication before changing.")
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.textSecondary)
                                .lineSpacing(2)
                        }

                        if isLoading {
                            ProgressView().tint(YomiTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else if categories.isEmpty {
                            YomiEmptyState(
                                icon: "folder.badge.plus",
                                title: "No Categories Yet",
                                message: "Create a shelf below to organize your library."
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(categories) { category in
                                    categoryRow(category)
                                }
                            }
                        }

                        createCategoryCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.danger)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().tint(YomiTheme.accentStrong).scaleEffect(0.7)
                        } else {
                            Text("Save")
                        }
                    }
                    .foregroundStyle(YomiTheme.accentStrong)
                    .disabled(isSaving || isLoading)
                }
            }
            .task { await load() }
        }
    }

    private func categoryRow(_ category: YomiCategory) -> some View {
        let isSelected = category.id.map { selectedIds.contains($0) } ?? false
        return Button {
            Task { await toggle(category) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? YomiTheme.accentStrong : YomiTheme.textTertiary)

                Text(category.name)
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)

                Spacer()

                if category.isLocked {
                    Image(systemName: privacyManager.isCategoryUnlocked(category) ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(YomiTheme.warning)
                }
            }
            .padding(13)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? YomiTheme.accent.opacity(0.5) : YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var createCategoryCard: some View {
        YomiCard(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                Text("New category")
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                HStack(spacing: 8) {
                    TextField("e.g. Favorites", text: $newCategoryName)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(YomiTheme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(YomiTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        createCategory()
                    } label: {
                        if isCreating {
                            ProgressView().tint(.white).scaleEffect(0.65)
                        } else {
                            Text("Create")
                        }
                    }
                    .buttonStyle(YomiPrimaryButtonStyle())
                    .disabled(isCreating || newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        categories = (try? await categoryRepo.getAllCategories()) ?? []
        selectedIds = Set((try? await categoryRepo.getCategoryIds(forMangaId: mangaId)) ?? [])
        isLoading = false
    }

    private func toggle(_ category: YomiCategory) async {
        guard let id = category.id else { return }

        if category.isLocked && !privacyManager.isCategoryUnlocked(category) {
            let success = await biometrics.requestUnlock(reason: "Unlock \(category.name)")
            guard success else { return }
            privacyManager.unlockCategory(category)
        }

        withAnimation(.easeOut(duration: 0.16)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        }
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreating else { return }
        isCreating = true

        Task {
            do {
                let category = try await categoryRepo.createCategory(name: name)
                categories = (try? await categoryRepo.getAllCategories()) ?? categories
                if let id = category.id {
                    selectedIds.insert(id)
                    try? await categoryRepo.setMangaCategories(mangaId: mangaId, categoryIds: Array(selectedIds))
                }
                newCategoryName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await categoryRepo.setMangaCategories(mangaId: mangaId, categoryIds: Array(selectedIds))
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Tracking

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
            var updated = track
            updated.status = status
            _ = try? await trackRepo.upsertTrack(updated)
            await loadTracks()
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
