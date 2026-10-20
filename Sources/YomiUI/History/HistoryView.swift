import SwiftUI
import YomiCore
import YomiDatabase

/// Chronological reading history with resume, filtering, and cleanup actions.
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

    private var uniqueTitles: Int {
        Set(historyItems.map(\.mangaId)).count
    }

    private var thisWeekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        return historyItems.filter { $0.readAt >= cutoff }.count
    }

    private var inProgressCount: Int {
        historyItems.filter { !$0.isRead }.count
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header

                        if privacyManager.isIncognitoMode {
                            incognitoBanner
                        }

                        summaryCard
                        controls

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
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
                .refreshable { await loadHistory(showsSpinner: false) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailManga) { manga in
                MangaDetailView(manga: manga)
            }
            .fullScreenCover(item: $readerRequest, onDismiss: {
                Task { await loadHistory(showsSpinner: false) }
            }) { request in
                ReaderContainerView(manga: request.manga, chapter: request.chapter)
            }
            .confirmationDialog(
                "Clear all reading history?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) { clearHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes history entries only. Reading progress and downloaded chapters are kept.")
            }
            .task { await loadHistory() }
        }
    }

    // MARK: - Header

    private var header: some View {
        YomiScreenHeader(title: "History", subtitle: headerSubtitle) {
            if !historyItems.isEmpty {
                Menu {
                    Button {
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
                }
                .buttonStyle(YomiIconButtonStyle())
            }
        }
    }

    private var headerSubtitle: String {
        if historyItems.isEmpty { return "Your reading trail, kept locally" }
        return "\(historyItems.count) chapters · \(uniqueTitles) titles"
    }

    private var incognitoBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Incognito is on · new reading sessions are not added to history")
                .font(YomiFont.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(YomiTheme.accentStrong)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(YomiTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Summary

    private var summaryCard: some View {
        YomiCard(padding: 16) {
            HStack(spacing: 12) {
                summaryStat(value: "\(thisWeekCount)", label: "This week", tint: YomiTheme.accentStrong)
                Divider().frame(height: 32).overlay(YomiTheme.border)
                summaryStat(value: "\(inProgressCount)", label: "In progress", tint: YomiTheme.warning)
                Divider().frame(height: 32).overlay(YomiTheme.border)
                summaryStat(value: "\(uniqueTitles)", label: "Titles", tint: YomiTheme.unreadBadge)
            }
        }
    }

    private func summaryStat(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(YomiFont.micro)
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            YomiSearchField(text: $searchQuery, placeholder: "Search history")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryFilter.allCases, id: \.self) { option in
                        YomiFilterChip(
                            title: option.title,
                            isSelected: filter == option,
                            icon: option.icon
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { filter = option }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private func historySection(_ section: HistoryDateSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)
                Text("\(section.items.count)")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(YomiTheme.surface)
                    .clipShape(Capsule())
                Spacer()
            }

            VStack(spacing: 9) {
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
                    cornerRadius: 10
                )
                .frame(width: 54, height: 78)
                .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
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
                        item.isRead ? "COMPLETED" : "PAGE \(item.lastPageRead + 1)",
                        tint: item.isRead ? YomiTheme.success : YomiTheme.accentStrong
                    )
                    Text(relativeTime(item.readAt))
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                }
            }

            Spacer(minLength: 2)

            Button {
                resume(item)
            } label: {
                Image(systemName: item.isRead ? "arrow.counterclockwise" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(YomiTheme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
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
            icon: "clock.badge.xmark",
            title: searchQuery.isEmpty ? "No Reading History" : "No Matches",
            message: searchQuery.isEmpty
                ? "Chapters you read will appear here so you can pick up instantly."
                : "Try a different title or clear the active history filter.",
            actionTitle: searchQuery.isEmpty ? nil : "Clear Search",
            action: searchQuery.isEmpty ? nil : { searchQuery = ""; filter = .all }
        )
    }

    // MARK: - Data

    private func loadHistory(showsSpinner: Bool = true) async {
        if showsSpinner { isLoading = true }
        do {
            historyItems = try await historyRepo.getHistory(limit: 400)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            try? await historyRepo.deleteHistoryItem(id: item.id)
            await loadHistory(showsSpinner: false)
        }
    }

    private func clearHistory() {
        Task {
            try? await historyRepo.clearAllHistory()
            await loadHistory(showsSpinner: false)
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

enum HistoryFilter: String, CaseIterable {
    case all = "All"
    case inProgress = "In Progress"
    case completed = "Completed"

    var title: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "clock.fill"
        case .inProgress: return "book.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }
}
