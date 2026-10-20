import SwiftUI
import YomiCore

/// Cross-source search. Runs sequentially so Cloudflare challenges are presented one at a time
/// instead of spawning a dozen competing verification sheets.
public struct GlobalSearchView: View {
    public let sources: [any SourceProtocol]

    @State private var query: String = ""
    @State private var selectedSourceId: Int64? = nil
    @State private var results: [SearchHit] = []
    @State private var isSearching: Bool = false
    @State private var searchedCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var failedCount: Int = 0
    @State private var currentSourceName: String = ""
    @State private var hasSearched: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration: Int = 0

    public init(sources: [any SourceProtocol]) {
        self.sources = sources
    }

    private var selectedSources: [any SourceProtocol] {
        guard let selectedSourceId else { return sources }
        return sources.filter { $0.manifest.id == selectedSourceId }
    }

    public var body: some View {
        ZStack {
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    YomiScreenHeader(
                        title: "Search",
                        subtitle: "Find a title across your installed sources"
                    )

                    searchControls

                    if isSearching {
                        searchingCard
                    }

                    if !results.isEmpty {
                        resultsSection
                    } else if hasSearched && !isSearching {
                        YomiEmptyState(
                            icon: "magnifyingglass",
                            title: "No Results",
                            message: failedCount > 0
                                ? "\(failedCount) source(s) could not be reached. Try again or search one source directly."
                                : "No titles matched this query. Check the spelling or switch sources.",
                            actionTitle: "Search Again",
                            action: { startSearch() }
                        )
                    } else if !hasSearched {
                        YomiEmptyState(
                            icon: "text.magnifyingglass",
                            title: "Search Every Source",
                            message: "Enter a title, author, or keyword. Yomi searches locally installed extensions one at a time."
                        )
                    }
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear { searchTask?.cancel() }
    }

    private var searchControls: some View {
        VStack(spacing: 10) {
            YomiSearchField(
                text: $query,
                placeholder: "Title, author, or keyword",
                onSubmit: { startSearch() }
            )

            HStack(spacing: 8) {
                Menu {
                    Button("All sources") { selectedSourceId = nil }
                    ForEach(sources.map { $0.manifest }, id: \.id) { manifest in
                        Button(manifest.name) { selectedSourceId = manifest.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .bold))
                        Text(selectedSourceName)
                            .font(YomiFont.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(YomiTheme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(YomiTheme.surface)
                    .overlay(Capsule().stroke(YomiTheme.border, lineWidth: 1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    if isSearching {
                        searchTask?.cancel()
                        searchGeneration += 1
                        isSearching = false
                    } else {
                        startSearch()
                    }
                } label: {
                    Text(isSearching ? "Stop" : "Search")
                }
                .buttonStyle(YomiPrimaryButtonStyle())
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching)
            }
        }
    }

    private var selectedSourceName: String {
        guard let selectedSourceId,
              let source = sources.first(where: { $0.manifest.id == selectedSourceId }) else {
            return "All sources"
        }
        return source.manifest.name
    }

    private var searchingCard: some View {
        YomiCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().tint(YomiTheme.accentStrong)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching \(currentSourceName)")
                            .font(YomiFont.cardTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text("\(searchedCount) of \(totalCount) sources")
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                    }
                    Spacer()
                    Text("\(results.count)")
                        .font(YomiFont.number)
                        .foregroundStyle(YomiTheme.accentStrong)
                }
                YomiProgressBar(
                    value: totalCount > 0 ? Double(searchedCount) / Double(totalCount) : 0,
                    tint: YomiTheme.accentStrong,
                    height: 4
                )
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YomiSectionHeader(
                "Results",
                subtitle: "\(results.count) across \(Set(results.map(\.sourceId)).count) source(s)"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108, maximum: 158), spacing: 12)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(results) { hit in
                    NavigationLink {
                        MangaDetailView(manga: hit.manga)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            MangaGridCard(manga: hit.manga, showsLibraryBadge: true)
                            Text(hit.sourceName)
                                .font(YomiFont.micro)
                                .foregroundStyle(YomiTheme.textTertiary)
                                .lineLimit(1)
                                .padding(.horizontal, 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        results = []
        failedCount = 0
        searchedCount = 0
        hasSearched = true
        isSearching = true

        let targetSources = selectedSources
        totalCount = targetSources.count

        searchTask = Task {
            var seen = Set<String>()
            for source in targetSources {
                if Task.isCancelled { break }
                await MainActor.run {
                    guard generation == searchGeneration else { return }
                    currentSourceName = source.manifest.name
                }

                do {
                    let page = try await source.searchManga(query: trimmed, filters: [], page: 1)
                    await MainActor.run {
                        // A stopped or superseded search must never leak results into the new one.
                        guard generation == searchGeneration else { return }
                        for manga in page.mangas {
                            guard !seen.contains(manga.stableId) else { continue }
                            seen.insert(manga.stableId)
                            results.append(
                                SearchHit(
                                    manga: manga,
                                    sourceId: source.manifest.id,
                                    sourceName: source.manifest.name
                                )
                            )
                        }
                        searchedCount += 1
                    }
                } catch {
                    await MainActor.run {
                        guard generation == searchGeneration else { return }
                        failedCount += 1
                        searchedCount += 1
                    }
                }
            }

            await MainActor.run {
                guard generation == searchGeneration else { return }
                isSearching = false
            }
        }
    }
}

private struct SearchHit: Identifiable {
    let manga: Manga
    let sourceId: Int64
    let sourceName: String
    var id: String { manga.stableId }
}
