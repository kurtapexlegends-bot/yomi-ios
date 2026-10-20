import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload

/// Minimalist offline download manager with queue controls and storage breakdown.
public struct DownloadsView: View {
    @State private var downloadManager = DownloadManager.shared
    @State private var groups: [DownloadedGroup] = []
    @State private var isLoading: Bool = true
    @State private var expandedGroups: Set<Int64> = []
    @State private var readerRequest: ReaderRequest?
    @State private var isShowingClearConfirmation: Bool = false
    @State private var errorMessage: String?

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()

    public init() {}

    private var activeJobs: [DownloadJob] {
        downloadManager.queue.filter { job in
            switch job.status {
            case .completed:
                return false
            case .queued, .downloading, .failed, .paused:
                return true
            }
        }
    }

    private var totalChapters: Int {
        groups.reduce(0) { $0 + $1.chapters.count }
    }

    private var totalBytes: Int64 {
        groups.reduce(0) { $0 + $1.byteCount }
    }

    public var body: some View {
        ZStack {
            YomiBackground(showsGlow: false)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !activeJobs.isEmpty {
                        queueSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.danger)
                    }

                    offlineSection

                    if totalChapters > 0 {
                        storageSummary
                    }
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .refreshable { await loadDownloads() }
        }
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await loadDownloads() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    if !downloadManager.queue.isEmpty {
                        Button {
                            downloadManager.clearFinishedJobs()
                        } label: {
                            Label("Clear Finished Queue", systemImage: "checklist")
                        }
                    }
                    if totalChapters > 0 {
                        Button(role: .destructive) {
                            isShowingClearConfirmation = true
                        } label: {
                            Label("Delete All Downloads", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YomiTheme.textSecondary)
                }
            }
        }
        .task { await loadDownloads() }
        .onChange(of: downloadManager.isProcessing) { _, processing in
            if !processing {
                Task { await loadDownloads() }
            }
        }
        .confirmationDialog(
            "Delete every downloaded chapter?",
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Downloads", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(totalChapters) offline chapters. Library entries and reading history stay on device.")
        }
        .yomiFullScreenCover(item: $readerRequest, onDismiss: {
            Task { await loadDownloads() }
        }) { request in
            ReaderContainerView(manga: request.manga, chapter: request.chapter)
        }
    }

    // MARK: - Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            YomiSectionHeader(
                "Download Queue",
                subtitle: downloadManager.isWaitingForWiFi
                    ? "Waiting for Wi-Fi · \(activeJobs.count) queued"
                    : "\(activeJobs.count) active"
            )

            VStack(spacing: 6) {
                ForEach(activeJobs) { job in
                    queueRow(job)
                }
            }
        }
    }

    private func queueRow(_ job: DownloadJob) -> some View {
        let statusText: String
        let statusTint: Color
        var progress: Float? = nil

        switch job.status {
        case .queued:
            statusText = "Queued"
            statusTint = YomiTheme.warning
        case .downloading(let value, let current, let total):
            progress = value
            statusText = total > 0 ? "\(current)/\(total) pages" : "Starting"
            statusTint = YomiTheme.accentStrong
        case .completed:
            statusText = "Completed"
            statusTint = YomiTheme.success
        case .failed:
            statusText = "Failed"
            statusTint = YomiTheme.danger
        case .paused:
            statusText = "Paused"
            statusTint = YomiTheme.textSecondary
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                YomiCoverImage(urlString: job.manga.effectiveThumbnailUrl, title: job.manga.title, cornerRadius: 6)
                    .frame(width: 36, height: 50)
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.manga.title)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)
                    Text(job.chapter.displayTitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                    Text(statusText)
                        .font(YomiFont.micro)
                        .foregroundStyle(statusTint)
                }

                Spacer(minLength: 2)

                if case .failed = job.status {
                    Button {
                        downloadManager.retry(jobId: job.id)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(YomiTheme.accentStrong)
                            .frame(width: 28, height: 28)
                            .background(YomiTheme.accentSoft)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    downloadManager.cancel(jobId: job.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(YomiTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(YomiTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let progress {
                YomiProgressBar(value: Double(progress), tint: YomiTheme.accentStrong, height: 2)
            }
        }
        .padding(10)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
    }

    // MARK: - Offline library

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader("Downloaded Titles", subtitle: "\(groups.count) title(s) · \(formattedBytes(totalBytes))")

            if isLoading && groups.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(YomiTheme.surface)
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall))
                    }
                }
            } else if groups.isEmpty {
                YomiEmptyState(
                    icon: "arrow.down.circle",
                    title: "No Downloads",
                    message: "Downloaded chapters are stored as standard CBZ archives and can be read fully offline."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(groups) { group in
                        downloadGroupCard(group)
                    }
                }
            }
        }
    }

    private func downloadGroupCard(_ group: DownloadedGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                NavigationLink {
                    MangaDetailView(manga: group.manga)
                } label: {
                    YomiCoverImage(
                        urlString: group.manga.effectiveThumbnailUrl,
                        title: group.manga.title,
                        cornerRadius: 6
                    )
                    .frame(width: 44, height: 62)
                    .clipped()
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.manga.title)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(group.chapters.count) chapter(s) · \(formattedBytes(group.byteCount))")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)

                    if let resume = group.resumeChapter {
                        Text("Resume: \(resume.displayTitle)")
                            .font(YomiFont.micro)
                            .foregroundStyle(YomiTheme.accentStrong)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        if isExpanded {
                            expandedGroups.remove(group.id)
                        } else {
                            expandedGroups.insert(group.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(YomiTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(YomiTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().overlay(YomiTheme.border)

                    ForEach(group.chapters) { item in
                        HStack(spacing: 10) {
                            Button {
                                readerRequest = ReaderRequest(manga: group.manga, chapter: item.chapter)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.chapter.read ? "checkmark.circle" : "circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(item.chapter.read ? YomiTheme.success : YomiTheme.textTertiary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.chapter.displayTitle)
                                            .font(YomiFont.body)
                                            .foregroundStyle(item.chapter.read ? YomiTheme.textSecondary : YomiTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(formattedBytes(item.byteCount))
                                            .font(YomiFont.micro)
                                            .foregroundStyle(YomiTheme.textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(YomiTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .background(YomiTheme.sunkenSurface)
            }
        }
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
    }

    private var storageSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(YomiTheme.textTertiary)

            Text("\(formattedBytes(totalBytes)) used across \(totalChapters) chapter(s)")
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)

            Spacer()

            Button("Delete All") {
                isShowingClearConfirmation = true
            }
            .font(YomiFont.caption.weight(.semibold))
            .foregroundStyle(YomiTheme.danger)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func loadDownloads() async {
        if groups.isEmpty { isLoading = true }

        let files = downloadManager.listDownloadedChapterFiles()
        let byManga = Dictionary(grouping: files, by: \.mangaId)
        var loaded: [DownloadedGroup] = []

        for (mangaId, mangaFiles) in byManga {
            guard let manga = try? await mangaRepo.getManga(id: mangaId) else { continue }
            let allChapters = (try? await chapterRepo.getChapters(forMangaId: mangaId)) ?? []
            let chapterMap = Dictionary(uniqueKeysWithValues: allChapters.compactMap { chapter in
                chapter.id.map { ($0, chapter) }
            })

            let items = mangaFiles.compactMap { file -> DownloadedChapterItem? in
                guard let chapter = chapterMap[file.chapterId] else { return nil }
                return DownloadedChapterItem(chapter: chapter, byteCount: file.byteCount, fileURL: file.fileURL)
            }
            .sorted { lhs, rhs in
                lhs.chapter.chapterNumber > rhs.chapter.chapterNumber
            }

            guard !items.isEmpty else { continue }
            loaded.append(
                DownloadedGroup(
                    manga: manga,
                    chapters: items,
                    byteCount: mangaFiles.reduce(0) { $0 + $1.byteCount }
                )
            )
        }

        groups = loaded.sorted {
            $0.manga.title.localizedCaseInsensitiveCompare($1.manga.title) == .orderedAscending
        }
        isLoading = false
    }

    private func delete(_ item: DownloadedChapterItem) {
        Task {
            for group in groups {
                if group.chapters.contains(where: { $0.id == item.id }) {
                    try? downloadManager.deleteDownloadedChapter(
                        chapterId: item.chapter.id ?? -1,
                        mangaId: group.manga.id ?? -1
                    )
                    break
                }
            }
            await loadDownloads()
        }
    }

    private func deleteAll() {
        do {
            try downloadManager.deleteAllDownloadedChapters()
            groups = []
            expandedGroups = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
