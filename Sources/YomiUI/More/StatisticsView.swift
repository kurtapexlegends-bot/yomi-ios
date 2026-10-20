import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

public struct StatisticsView: View {
    @State private var libraryCount: Int = 0
    @State private var totalChapters: Int = 0
    @State private var readChapters: Int = 0
    @State private var bookmarkCount: Int = 0
    @State private var completedTitles: Int = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var downloadedChapters: Int = 0
    @State private var sourceCounts: [SourceCount] = []
    @State private var isLoading: Bool = true

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let extensionManager = ExtensionManager.shared
    private let downloadManager = DownloadManager.shared

    public init() {}

    private var completionFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(readChapters) / Double(totalChapters)
    }

    public var body: some View {
        ZStack {
            YomiBackground()

            if isLoading {
                ProgressView("Calculating your footprint...")
                    .font(YomiFont.body)
                    .tint(YomiTheme.accent)
                    .foregroundStyle(YomiTheme.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        YomiScreenHeader(
                            title: "Statistics",
                            subtitle: "A quiet record of what you have read"
                        )

                        heroCard

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            statCard(
                                value: "\(libraryCount)",
                                label: "Library titles",
                                icon: "books.vertical.fill",
                                tint: YomiTheme.accentStrong
                            )
                            statCard(
                                value: "\(totalChapters)",
                                label: "Chapters tracked",
                                icon: "list.bullet.rectangle",
                                tint: YomiTheme.unreadBadge
                            )
                            statCard(
                                value: "\(bookmarkCount)",
                                label: "Bookmarked",
                                icon: "bookmark.fill",
                                tint: YomiTheme.warning
                            )
                            statCard(
                                value: "\(completedTitles)",
                                label: "Completed titles",
                                icon: "checkmark.seal.fill",
                                tint: YomiTheme.success
                            )
                            statCard(
                                value: "\(downloadedChapters)",
                                label: "Offline chapters",
                                icon: "arrow.down.circle.fill",
                                tint: YomiTheme.success
                            )
                            statCard(
                                value: ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file),
                                label: "Offline storage",
                                icon: "internaldrive.fill",
                                tint: YomiTheme.warning
                            )
                        }

                        if !sourceCounts.isEmpty {
                            sourceSection
                        }

                        Text("Statistics are calculated locally. Yomi never uploads your reading data.")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, YomiTheme.contentPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Statistics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var heroCard: some View {
        YomiCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        YomiEyebrow("TOTAL READ")
                        Text("\(readChapters)")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(YomiTheme.textPrimary)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(max(0, totalChapters - readChapters))")
                            .font(YomiFont.sectionTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("unread")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Library completion")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                        Spacer()
                        Text("\(Int(completionFraction * 100))%")
                            .font(YomiFont.number)
                            .foregroundStyle(YomiTheme.accentStrong)
                    }
                    YomiProgressBar(value: completionFraction, tint: YomiTheme.accentStrong, height: 6)
                }
            }
        }
    }

    private func statCard(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(YomiTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YomiSectionHeader("Top sources", subtitle: "Where your library comes from")
            VStack(spacing: 10) {
                ForEach(sourceCounts) { source in
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YomiTheme.accentStrong)
                            .frame(width: 30, height: 30)
                            .background(YomiTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(source.name)
                            .font(YomiFont.body.weight(.semibold))
                            .foregroundStyle(YomiTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(source.count)")
                            .font(YomiFont.number)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(YomiTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        let mangas = (try? await mangaRepo.getLibraryMangas()) ?? []
        let progress = (try? await chapterRepo.getLibraryProgress()) ?? [:]
        let downloadedFiles = downloadManager.listDownloadedChapterFiles()

        var sourceCounter: [Int64: Int] = [:]
        for manga in mangas {
            sourceCounter[manga.sourceId, default: 0] += 1
        }
        let sourceNames = sourceCounter.map { sourceId, count in
            let name = extensionManager.getSource(id: sourceId)?.manifest.name ?? "Unknown source"
            return SourceCount(name: name, count: count)
        }
        .sorted { $0.count > $1.count }
        .prefix(5)

        libraryCount = mangas.count
        totalChapters = progress.values.reduce(0) { $0 + $1.totalChapters }
        readChapters = progress.values.reduce(0) { $0 + $1.readChapters }
        bookmarkCount = progress.values.reduce(0) { $0 + $1.bookmarkedChapters }
        completedTitles = progress.values.filter(\.isCompleted).count
        downloadedBytes = downloadedFiles.reduce(0) { $0 + $1.byteCount }
        downloadedChapters = downloadedFiles.count
        sourceCounts = Array(sourceNames)
        isLoading = false
    }
}

private struct SourceCount: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}
