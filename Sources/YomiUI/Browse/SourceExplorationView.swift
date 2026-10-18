import SwiftUI
import YomiCore
import YomiDatabase

public struct SourceExplorationView: View {
    public let source: any SourceProtocol

    @State private var mangas: [Manga] = []
    @State private var filterMode: Int = 0 // 0 = Popular, 1 = Latest
    @State private var searchQuery: String = ""
    @State private var currentPage: Int = 1
    @State private var hasNextPage: Bool = true
    @State private var isLoading: Bool = false
    @State private var selectedManga: Manga?

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
                    ProgressView()
                    Spacer()
                } else if mangas.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(YomiTheme.textSecondary)
                        Text("No Manga Found")
                            .font(.headline)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(mangas) { manga in
                                MangaCardView(manga: manga)
                                    .onTapGesture {
                                        saveAndNavigate(to: manga)
                                    }
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
                }
            }
        }
        .navigationTitle(source.manifest.name)
        .searchable(text: $searchQuery, prompt: "Search \(source.manifest.name)...")
        .onSubmit(of: .search) {
            resetAndFetch()
        }
        .onAppear {
            if mangas.isEmpty { resetAndFetch() }
        }
        .navigationDestination(item: $selectedManga) { manga in
            MangaDetailView(manga: manga)
        }
    }

    private func resetAndFetch() {
        currentPage = 1
        mangas = []
        hasNextPage = true
        fetchNextPage()
    }

    private func fetchNextPage() {
        guard !isLoading && hasNextPage else { return }
        isLoading = true

        Task {
            do {
                let result: MangaPageResult
                if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result = try await source.searchManga(query: searchQuery, filters: [], page: currentPage)
                } else if filterMode == 0 {
                    result = try await source.getPopularManga(page: currentPage)
                } else {
                    result = try await source.getLatestUpdates(page: currentPage)
                }

                self.mangas.append(contentsOf: result.mangas)
                self.hasNextPage = result.hasNextPage
                self.currentPage += 1
            } catch {
                print("[SourceExploration] Error fetching page \(currentPage): \(error)")
            }
            self.isLoading = false
        }
    }

    private func saveAndNavigate(to manga: Manga) {
        Task {
            let saved = (try? await mangaRepo.upsert(manga)) ?? manga
            self.selectedManga = saved
        }
    }
}
