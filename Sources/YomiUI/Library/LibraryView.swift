import SwiftUI
import YomiCore
import YomiDatabase

public struct LibraryView: View {
    @State private var mangas: [Manga] = []
    @State private var categories: [Category] = []
    @State private var selectedCategoryId: Int64? = nil
    @State private var searchQuery: String = ""
    @State private var isLoading: Bool = false
    @State private var selectedMangaForDetail: Manga?

    private let mangaRepo = MangaRepository()
    private let categoryRepo = CategoryRepository()
    private let privacyManager = PrivacyManager.shared
    private let biometricManager = BiometricSecurityManager.shared

    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 160), spacing: 12)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Incognito Banner
                if privacyManager.isIncognitoMode {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                        Text("Incognito Mode Active — History and tracking paused")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.8))
                    .foregroundStyle(.white)
                }

                // Category Tabs Bar
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryPill(
                                title: "All",
                                isSelected: selectedCategoryId == nil,
                                isLocked: false
                            ) {
                                selectedCategoryId = nil
                                loadMangas()
                            }

                            ForEach(categories) { cat in
                                CategoryPill(
                                    title: cat.name,
                                    isSelected: selectedCategoryId == cat.id,
                                    isLocked: cat.isLocked && !privacyManager.isCategoryUnlocked(cat)
                                ) {
                                    handleCategoryTap(cat)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(YomiTheme.surface.opacity(0.5))
                }

                // Manga Grid Content
                Group {
                    if isLoading {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else if mangas.isEmpty {
                        EmptyLibraryState(searchQuery: searchQuery)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(mangas) { manga in
                                    MangaCardView(manga: manga)
                                        .onTapGesture {
                                            selectedMangaForDetail = manga
                                        }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchQuery, prompt: "Search titles, authors...")
            .onChange(of: searchQuery) { _, newQuery in
                searchLibrary(query: newQuery)
            }
            .refreshable {
                await refreshLibrary()
            }
            .onAppear {
                loadInitialData()
            }
            .navigationDestination(item: $selectedMangaForDetail) { manga in
                MangaDetailView(manga: manga)
            }
        }
    }

    private func loadInitialData() {
        Task {
            categories = (try? await categoryRepo.getAllCategories()) ?? []
            loadMangas()
        }
    }

    private func loadMangas() {
        isLoading = true
        Task {
            if let catId = selectedCategoryId {
                mangas = (try? await mangaRepo.getLibraryMangas(forCategoryId: catId)) ?? []
            } else {
                mangas = (try? await mangaRepo.getLibraryMangas()) ?? []
            }
            isLoading = false
        }
    }

    private func searchLibrary(query: String) {
        Task {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadMangas()
            } else {
                mangas = (try? await mangaRepo.searchFTS(query: query)) ?? []
            }
        }
    }

    private func handleCategoryTap(_ category: Category) {
        if category.isLocked && !privacyManager.isCategoryUnlocked(category) {
            Task {
                let success = await biometricManager.requestUnlock(reason: "Unlock \(category.name)")
                if success {
                    privacyManager.unlockCategory(category)
                    selectedCategoryId = category.id
                    loadMangas()
                }
            }
        } else {
            selectedCategoryId = category.id
            loadMangas()
        }
    }

    private func refreshLibrary() async {
        loadMangas()
    }
}

// MARK: - Subviews

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? YomiTheme.accent : YomiTheme.surface)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

public struct MangaCardView: View {
    public let manga: Manga

    public init(manga: Manga) {
        self.manga = manga
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                // Cover Image
                AsyncImage(url: URL(string: manga.effectiveThumbnailUrl ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle()
                            .fill(YomiTheme.surface)
                            .overlay(
                                Image(systemName: "book.closed")
                                    .font(.title2)
                                    .foregroundStyle(YomiTheme.textSecondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(minHeight: 155, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))

                // Subtle gradient overlay for title legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))

                Text(manga.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .contextMenu {
            Button {
                Task {
                    try? await MangaRepository().setInLibrary(mangaId: manga.id ?? 0, inLibrary: false)
                }
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }
}

struct EmptyLibraryState: View {
    let searchQuery: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchQuery.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(YomiTheme.textSecondary)
            Text(searchQuery.isEmpty ? "Your Library is Empty" : "No Results Found")
                .font(.headline)
            Text(searchQuery.isEmpty ? "Browse sources or explore extensions to add manga to your library." : "Try searching for a different keyword.")
                .font(.subheadline)
                .foregroundStyle(YomiTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
