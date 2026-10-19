import SwiftUI
import YomiCore
import YomiDatabase

public struct SourceExplorationView: View {
    public let source: any SourceProtocol

    @State private var mangas: [Manga] = []
    @State private var libraryMangaUrls: Set<String> = []
    @State private var filterMode: Int = 0 // 0 = Popular, 1 = Latest
    @State private var searchQuery: String = ""
    @State private var currentPage: Int = 1
    @State private var hasNextPage: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var availableFilters: [Filter] = []
    @State private var appliedFilters: [Filter] = []
    @State private var isFilterSheetPresented: Bool = false

    private var hasActiveFilters: Bool {
        appliedFilters.contains { !$0.isDefault }
    }

    private let mangaRepo = MangaRepository()
    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 160), spacing: 12)]

    public init(source: any SourceProtocol) {
        self.source = source
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $filterMode) {
                Text("Popular").tag(0)
                if source.manifest.supportsLatest {
                    Text("Latest").tag(1)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: filterMode) { _, _ in
                resetAndFetch()
            }

            Group {
                if isLoading && mangas.isEmpty {
                    Spacer()
                    ProgressView("Loading \(source.manifest.name)...")
                        .foregroundStyle(YomiTheme.textSecondary)
                    Spacer()
                } else if let error = errorMessage, mangas.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(YomiTheme.accent)
                        Text("Failed to Load")
                            .font(.headline)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            resetAndFetch()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(YomiTheme.accent)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .padding(.top, 4)
                        Spacer()
                    }
                } else if mangas.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(YomiTheme.textSecondary)
                        Text("No Manga Found")
                            .font(.headline)
                            .foregroundStyle(YomiTheme.textPrimary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(mangas, id: \.stableId) { manga in
                                let displayManga = resolvedManga(manga)
                                NavigationLink(value: displayManga) {
                                    MangaCardView(manga: displayManga, onToggleLibrary: {
                                        loadLibraryUrls()
                                    })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)

                        if hasNextPage {
                            ProgressView()
                                .padding()
                                .onAppear {
                                    fetchNextPage()
                                }
                        }
                    }
                    .refreshable {
                        resetAndFetch()
                    }
                }
            }
        }
        .navigationTitle(source.manifest.name)
        .searchable(text: $searchQuery, prompt: "Search \(source.manifest.name)...")
        .onSubmit(of: .search) {
            resetAndFetch()
        }
        .onChange(of: searchQuery) { _, newQuery in
            if newQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resetAndFetch()
            }
        }
        .toolbar {
            if !availableFilters.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isFilterSheetPresented = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasActiveFilters ? YomiTheme.accent : YomiTheme.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            SourceFilterSheet(
                currentFilters: appliedFilters,
                defaultFilters: availableFilters,
                onApply: { updated in
                    appliedFilters = updated
                    resetAndFetch()
                },
                onReset: {
                    appliedFilters = availableFilters
                    resetAndFetch()
                }
            )
        }
        .onAppear {
            loadLibraryUrls()
            if availableFilters.isEmpty {
                let filters = source.getFilters()
                self.availableFilters = filters
                self.appliedFilters = filters
            }
            if mangas.isEmpty { resetAndFetch() }
        }
        .navigationDestination(for: Manga.self) { manga in
            MangaDetailView(manga: manga)
        }
    }

    private func resolvedManga(_ manga: Manga) -> Manga {
        var copy = manga
        if libraryMangaUrls.contains(manga.url) {
            copy.inLibrary = true
        }
        return copy
    }

    private func loadLibraryUrls() {
        Task {
            if let libMangas = try? await mangaRepo.getLibraryMangas() {
                self.libraryMangaUrls = Set(libMangas.map(\.url))
            }
        }
    }

    private func resetAndFetch() {
        currentPage = 1
        mangas = []
        errorMessage = nil
        hasNextPage = true
        fetchNextPage()
    }

    private func fetchNextPage() {
        guard !isLoading && hasNextPage else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result: MangaPageResult
                let hasQuery = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasQuery || hasActiveFilters {
                    result = try await source.searchManga(query: searchQuery, filters: appliedFilters, page: currentPage)
                } else if filterMode == 0 {
                    result = try await source.getPopularManga(page: currentPage)
                } else {
                    result = try await source.getLatestUpdates(page: currentPage)
                }

                let existingIds = Set(self.mangas.map(\.stableId))
                let uniqueNew = result.mangas.filter { !existingIds.contains($0.stableId) }
                self.mangas.append(contentsOf: uniqueNew)
                self.hasNextPage = result.hasNextPage
                self.currentPage += 1
            } catch {
                print("[SourceExploration] Error fetching page \(currentPage): \(error)")
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
