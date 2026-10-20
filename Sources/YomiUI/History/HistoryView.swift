import SwiftUI
import YomiCore
import YomiDatabase

/// Chronological reading history with instant resume, search, and cleanup actions.
public struct HistoryView: View {
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoading: Bool = false
    @State private var searchQuery: String = ""
    @State private var filter: HistoryFilter = .all
    @State private var showingClearConfirmation: Bool = false
    @State private var readerRequest: ReaderRequest?
    @State private var detailManga: Manga?
    @State private var errorMessage: String?

    private let historyRepo = HistoryRepository()
    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let privacyManager = PrivacyManager.shared

    public init() {}

    private var filteredHistory: [HistoryItem] {
        var items = historyItems

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter {
                $0.mangaTitle.localizedCaseInsensitiveContains(query)
                    || $0.chapterName.localizedCaseInsensitiveContains(query)
            }
        }

        switch filter {
        case .all:
            break
        case .inProgress:
            items = items.filter { !$0.isRead }
        case .completed:
            items = items.filter(\.isRead)
        }

        return items
    }

    private var sections: [HistoryDateSection] {
        let calendar = Calendar.current
        var today: [HistoryItem] = []
        var yesterday: [HistoryItem] = []
        var week: [HistoryItem] = []
        var older: [HistoryItem] = []

        for item in filteredHistory {
            if calendar.isDateInToday(item.readAt) {
                today.append(item)
            } else if calendar.isDateInYesterday(item.readAt) {
                yesterday.append(item)
            } else if let days = calendar.dateComponents([.day], from: item.readAt, to: Date()).day, days <= 7 {
                week.append(item)
            } else {
                older.append(item)
            }
        }

        var result: [HistoryDateSection] = []
        if !today.isEmpty { result.append(HistoryDateSection(title: "Today", items: today)) }
        if !yesterday.isEmpty { result.append(HistoryDateSection(title: "Yesterday", items: yesterday)) }
        if !week.isEmpty { result.append(HistoryDateSection(title: "Earlier This Week", items: week)) }
        if !older.isEmpty { result.append(HistoryDateSection(title: "Older", items: older)) }
        return result
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                VStack(spacing: 0) {
                    filterBar

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if privacyManager.isIncognitoMode {
                                incognitoNotice
                            }

                            if isLoading && historyItems.isEmpty {
                                ProgressView()
                                    .tint(YomiTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            } else if filteredHistory.isEmpty {
                                emptyState
                            } else {
                                ForEach(sections, id: \.title) { section in
                                    historySection(section)
                                }
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(YomiFont.caption)
                                    .foregroundStyle(YomiTheme.danger)
                            }
                        }
                        .padding(.horizontal, YomiTheme.contentPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await loadHistory() }
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !historyItems.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                showingClearConfirmation = true
                            } label: {
                                Label("Clear All History", systemImage: "trash")
                            }
                            Button {
                                Task { await loadHistory() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search history")
            .navigationDestination(item: $detailManga) { manga in
                MangaDetailView(manga: manga)
            }
            .yomiFullScreenCover(item: $readerRequest, onDismiss: {
                Task { await loadHistory() }
            }) { request in
                ReaderContainerView(manga: request.manga, chapter: request.chapter)
            }
            .confirmationDialog(
                "Clear entire reading history?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    clearAllHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Titles in your library and downloaded chapters are kept.")
            }
            .task { await loadHistory() }
        }
    }

    // MARK: - Subviews

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases, id: \.self) { option in
                    YomiFilterChip(
                        title: option.title,
                        isSelected: filter == option,
                        icon: nil
                    ) {
                        filter = option
                    }
                }
            }
            .padding(.horizontal, YomiTheme.contentPadding)
            .padding(.vertical, 8)
        }
        .background(YomiTheme.pureBlack)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
    }

    private var incognitoNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .medium))
            Text("Incognito · Reading activity is not logged")
                .font(YomiFont.caption)
        }
        .foregroundStyle(YomiTheme.accentStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(YomiTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func historySection(_ section: HistoryDateSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.title)
                    .font(YomiFont.micro)
                    .tracking(1.2)
                    .foregroundStyle(YomiTheme.textTertiary)
                Spacer()
                Text("\(section.items.count)")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
            }
            .padding(.top, 4)

            LazyVStack(spacing: 0) {
                ForEach(section.items) { item in
                    historyRow(item)
                }
            }
        }
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: 12) {
            Button {
                openDetail(for: item)
            } label: {
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

                Text(item.displayChapterTitle)
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    YomiTag(
                        item.isRead ? "COMPLETED" : "P. \(item.lastPageRead + 1)",
                        tint: item.isRead ? YomiTheme.success : YomiTheme.accentStrong
                    )
                    Text(relativeTime(item.readAt))
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                }
            }

            Spacer(minLength: 4)

            Button {
                resume(item)
            } label: {
                Image(systemName: item.isRead ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(YomiTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(YomiTheme.border).frame(height: 0.5)
        }
        .contextMenu {
            Button {
                resume(item)
            } label: {
                Label(item.isRead ? "Read Again" : "Resume Reading", systemImage: "book.fill")
            }
            Button {
                openDetail(for: item)
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            Button(role: .destructive) {
                deleteHistory(item)
            } label: {
                Label("Remove from History", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        YomiEmptyState(
            icon: "clock.arrow.circlepath",
            title: historyItems.isEmpty ? "No Reading History" : "No Matching History",
            message: historyItems.isEmpty
                ? "Chapters you read will appear here with instant resume."
                : "No history entries match your current filter.",
            actionTitle: historyItems.isEmpty ? nil : "Clear Filter",
            action: historyItems.isEmpty ? nil : { filter = .all }
        )
    }

    // MARK: - Actions

    private func loadHistory() async {
        isLoading = true
        historyItems = (try? await historyRepo.getHistory(limit: 250)) ?? []
        isLoading = false
    }

    private func resume(_ item: HistoryItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId),
                  let chapter = try? await chapterRepo.getChapter(id: item.chapterId) else { return }
            await MainActor.run {
                readerRequest = ReaderRequest(manga: manga, chapter: chapter)
            }
        }
    }

    private func openDetail(for item: HistoryItem) {
        Task {
            guard let manga = try? await mangaRepo.getManga(id: item.mangaId) else { return }
            await MainActor.run {
                detailManga = manga
            }
        }
    }

    private func deleteHistory(_ item: HistoryItem) {
        Task {
            try? await historyRepo.deleteHistory(forMangaId: item.mangaId)
            await loadHistory()
        }
    }

    private func clearAllHistory() {
        Task {
            try? await historyRepo.clearAllHistory()
            await loadHistory()
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Models

private struct HistoryDateSection {
    let title: String
    let items: [HistoryItem]
}

public enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case inProgress = "In Progress"
    case completed = "Finished"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "clock"
        case .inProgress: return "bookmark.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}
