import SwiftUI
import YomiCore
import YomiDatabase

/// Displays reading history grouped chronologically with quick resume actions.
public struct HistoryView: View {
    @State private var historyItems: [HistoryItem] = []
    @State private var isLoading: Bool = false
    @State private var showingClearConfirmation: Bool = false
    @State private var activeChapterForReading: Chapter?
    @State private var activeMangaForReading: Manga?
    @State private var selectedMangaForDetail: Manga?

    private let historyRepo = HistoryRepository()
    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let privacyManager = PrivacyManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Incognito Mode Banner
                if privacyManager.isIncognitoMode {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                        Text("Incognito Mode Active — History is not recorded")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.85))
                    .foregroundStyle(.white)
                }

                if isLoading && historyItems.isEmpty {
                    Spacer()
                    ProgressView("Loading history...")
                        .foregroundStyle(YomiTheme.textSecondary)
                    Spacer()
                } else if historyItems.isEmpty {
                    EmptyHistoryView()
                } else {
                    List {
                        let sections = groupHistoryByDate(historyItems)
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.items) { item in
                                    HistoryRowView(
                                        item: item,
                                        onResume: {
                                            resumeReading(for: item)
                                        },
                                        onViewManga: {
                                            openMangaDetail(for: item)
                                        }
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteItem(item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                    .refreshable {
                        await reloadHistory()
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !historyItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.red)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear History",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Reading History", role: .destructive) {
                    clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action will remove all reading history records. Your library manga and bookmarks will not be affected.")
            }
            .onAppear {
                loadHistory()
            }
            .navigationDestination(item: $selectedMangaForDetail) { manga in
                MangaDetailView(manga: manga)
            }
            #if os(iOS)
            .fullScreenCover(item: $activeChapterForReading) { chapter in
                if let manga = activeMangaForReading {
                    ReaderContainerView(manga: manga, chapter: chapter)
                }
            }
            #else
            .sheet(item: $activeChapterForReading) { chapter in
                if let manga = activeMangaForReading {
                    ReaderContainerView(manga: manga, chapter: chapter)
                }
            }
            #endif
            .onChange(of: activeChapterForReading) { oldVal, newVal in
                if oldVal != nil && newVal == nil {
                    loadHistory()
                }
            }
        }
    }

    private func loadHistory() {
        isLoading = true
        Task {
            historyItems = (try? await historyRepo.getHistory(limit: 100)) ?? []
            isLoading = false
        }
    }

    private func reloadHistory() async {
        historyItems = (try? await historyRepo.getHistory(limit: 100)) ?? []
    }

    private func deleteItem(_ item: HistoryItem) {
        Task {
            try? await historyRepo.deleteHistoryItem(id: item.id)
            if let idx = historyItems.firstIndex(where: { $0.id == item.id }) {
                historyItems.remove(at: idx)
            }
        }
    }

    private func clearAll() {
        Task {
            try? await historyRepo.clearAllHistory()
            historyItems.removeAll()
        }
    }

    private func resumeReading(for item: HistoryItem) {
        Task {
            if let manga = try? await mangaRepo.getManga(id: item.mangaId),
               let chapter = try? await chapterRepo.getChapter(id: item.chapterId) {
                self.activeMangaForReading = manga
                self.activeChapterForReading = chapter
            }
        }
    }

    private func openMangaDetail(for item: HistoryItem) {
        Task {
            if let manga = try? await mangaRepo.getManga(id: item.mangaId) {
                self.selectedMangaForDetail = manga
            }
        }
    }

    private func groupHistoryByDate(_ items: [HistoryItem]) -> [HistoryDateSection] {
        let calendar = Calendar.current
        var today: [HistoryItem] = []
        var yesterday: [HistoryItem] = []
        var thisWeek: [HistoryItem] = []
        var older: [HistoryItem] = []

        let now = Date()
        for item in items {
            let itemDate = item.readAt
            if calendar.isDateInToday(itemDate) {
                today.append(item)
            } else if calendar.isDateInYesterday(itemDate) {
                yesterday.append(item)
            } else if let daysAgo = calendar.dateComponents([.day], from: itemDate, to: now).day, daysAgo <= 7 {
                thisWeek.append(item)
            } else {
                older.append(item)
            }
        }

        var sections: [HistoryDateSection] = []
        if !today.isEmpty { sections.append(HistoryDateSection(title: "Today", items: today)) }
        if !yesterday.isEmpty { sections.append(HistoryDateSection(title: "Yesterday", items: yesterday)) }
        if !thisWeek.isEmpty { sections.append(HistoryDateSection(title: "Earlier This Week", items: thisWeek)) }
        if !older.isEmpty { sections.append(HistoryDateSection(title: "Older", items: older)) }
        return sections
    }
}

// MARK: - Subviews & Models

struct HistoryDateSection {
    let title: String
    let items: [HistoryItem]
}

struct HistoryRowView: View {
    let item: HistoryItem
    let onResume: () -> Void
    let onViewManga: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Manga Cover Thumbnail
            AsyncImage(url: URL(string: item.effectiveThumbnailUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(YomiTheme.surface)
                        .overlay(Image(systemName: "book.closed").font(.caption).foregroundStyle(YomiTheme.textSecondary))
                }
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .clipped()
            .onTapGesture {
                onViewManga()
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.mangaTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)

                Text(item.displayChapterTitle)
                    .font(.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.isRead ? "Completed" : "Page \(item.lastPageRead + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(item.isRead ? YomiTheme.downloadBadge : YomiTheme.accent)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(YomiTheme.textSecondary)

                    Text(formatTime(item.readAt))
                        .font(.caption2)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onResume()
            }

            Spacer()

            // Quick Resume Button
            Button(action: onResume) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(YomiTheme.accent)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                onResume()
            } label: {
                Label("Resume Reading", systemImage: "play.fill")
            }

            Button {
                onViewManga()
            } label: {
                Label("View Manga Details", systemImage: "info.circle")
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(YomiTheme.textSecondary)
            Text("No Reading History")
                .font(.headline)
                .foregroundStyle(YomiTheme.textPrimary)
            Text("Chapters you read will appear here so you can easily resume where you left off.")
                .font(.subheadline)
                .foregroundStyle(YomiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
