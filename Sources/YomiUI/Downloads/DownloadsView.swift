import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload

/// Download center with active transfer progress and a fully offline library.
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
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    summaryCard

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
                        storageCard
                    }
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 10)
                .padding(.bottom, 34)
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
                        .font(.system(size: 15, weight: .semibold))
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
            Text("This removes \(totalChapters) offline chapter(s) from this device. Library entries and reading progress stay intact.")
        }
        .yomiFullScreenCover(item: $readerRequest, onDismiss: {
            Task { await loadDownloads() }
        }) { request in
            ReaderContainerView(manga: request.manga, chapter: request.chapter)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        YomiCard(padding: 17) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(YomiTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline library")
                            .font(YomiFont.cardTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("Read without a connection or source")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: 0) {
                    summaryStat(value: "\(totalChapters)", label: "Chapters", tint: YomiTheme.accentStrong)
                    summaryDivider
                    summaryStat(value: "\(groups.count)", label: "Titles", tint: YomiTheme.success)
                    summaryDivider
                    summaryStat(value: formattedBytes(totalBytes), label: "Storage", tint: YomiTheme.warning)
                    summaryDivider
                    summaryStat(value: "\(activeJobs.count)", label: "Active", tint: YomiTheme.unreadBadge)
                }
            }
        }
    }

    private func summaryStat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(YomiFont.micro)
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(YomiTheme.border)
            .frame(width: 1, height: 27)
            .padding(.horizontal, 7)
    }

    // MARK: - Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            YomiSectionHeader("Download Queue", subtitle: "\(activeJobs.count) job(s)")

            VStack(spacing: 8) {
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

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                YomiCoverImage(urlString: job.manga.effectiveThumbnailUrl, title: job.manga.title, cornerRadius: 8)
                    .frame(width: 40, height: 56)
                    .clipped()

                VStack(alignment: .leading, spacing: 3) {
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YomiTheme.accentStrong)
                            .frame(width: 32, height: 32)
                            .background(YomiTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    downloadManager.cancel(jobId: job.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YomiTheme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(YomiTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let progress {
                YomiProgressBar(value: Double(progress), tint: YomiTheme.accentStrong, height: 4)
            }
        }
        .padding(12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Offline library

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            YomiSectionHeader("Downloaded Titles", subtitle: "\(groups.count) title(s)")

            if isLoading && groups.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(YomiTheme.surface)
                            .frame(height: 88)
                    }
                }
            } else if groups.isEmpty {
                YomiEmptyState(
                    icon: "arrow.down.circle",
                    title: "No Downloads Yet",
                    message: "Open a title and tap the download button to keep chapters on this device for offline reading."
                )
            } else {
                LazyVStack(spacing: 9) {
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
                        cornerRadius: 10
                    )
                    .frame(width: 48, height: 68)
                    .clipped()
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.manga.title)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)

                    Text("\(group.chapters.count) chapter(s) · \(formattedBytes(group.byteCount))")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)

                    HStack(spacing: 6) {
                        YomiTag("OFFLINE", tint: YomiTheme.success)
                        if let resume = group.resumeChapter {
                            Text(resume.displayTitle)
                                .font(YomiFont.micro)
                                .foregroundStyle(YomiTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 2)

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        if isExpanded {
                            expandedGroups.remove(group.id)
                        } else {
                            expandedGroups.insert(group.id)
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YomiTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(YomiTheme.elevatedSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if let resume = group.resumeChapter {
                Button {
                    readerRequest = ReaderRequest(manga: group.manga, chapter: resume)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Read \(resume.displayTitle)")
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(YomiPrimaryButtonStyle())
                .padding(.horizontal, 12)
                .padding(.bottom, 11)
            }

            if isExpanded {
                Divider().overlay(YomiTheme.border)

                VStack(spacing: 2) {
                    ForEach(group.chapters) { item in
                        HStack(spacing: 9) {
                            Button {
                                readerRequest = ReaderRequest(manga: group.manga, chapter: item.chapter)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.chapter.read ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(item.chapter.read ? YomiTheme.success : YomiTheme.textTertiary)

                                    Text(item.chapter.displayTitle)
                                        .font(YomiFont.caption)
                                        .foregroundStyle(YomiTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(formattedBytes(item.byteCount))
                                        .font(YomiFont.micro)
                                        .foregroundStyle(YomiTheme.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(YomiTheme.textTertiary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 5)
            }
        }
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var storageCard: some View {
        YomiCard(padding: 14) {
            HStack(spacing: 11) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(YomiTheme.warning)
                    .frame(width: 36, height: 36)
                    .background(YomiTheme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloaded storage")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text("\(formattedBytes(totalBytes)) across \(totalChapters) chapter(s)")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                Spacer()
                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Text("Manage")
                }
                .buttonStyle(YomiSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Data

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

private struct DownloadedGroup: Identifiable {
    var id: Int64 { manga.id ?? 0 }
    let manga: Manga
    let chapters: [DownloadedChapterItem]
    let byteCount: Int64

    var resumeChapter: Chapter? {
        chapters.first(where: { !$0.chapter.read && $0.chapter.lastPageRead > 0 })?.chapter
            ?? chapters.first(where: { !$0.chapter.read })?.chapter
            ?? chapters.first?.chapter
    }
}

private struct DownloadedChapterItem: Identifiable {
    var id: Int64 { chapter.id ?? 0 }
    let chapter: Chapter
    let byteCount: Int64
    let fileURL: URL
}
