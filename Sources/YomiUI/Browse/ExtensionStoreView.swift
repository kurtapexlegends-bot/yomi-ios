import SwiftUI
import YomiCore
import YomiExtensions
import YomiDatabase

public struct ExtensionStoreView: View {
    @State private var repos: [ExtensionRepo] = []
    @State private var availablePackages: [RemoteExtensionPackage] = []
    @State private var isLoading: Bool = false
    @State private var isShowingAddRepoAlert: Bool = false
    @State private var newRepoURL: String = ""
    @State private var searchQuery: String = ""
    @State private var selectedLanguage: String = "all"
    @State private var availableLanguages: [String] = ["all"]
    @State private var errorMessage: String?
    @State private var isShowingErrorAlert: Bool = false
    @State private var installingPackageIds: Set<Int64> = []

    private let repoRepo = ExtensionRepoRepository()
    private let repoManager = RepoManager.shared
    private let extensionManager = ExtensionManager.shared

    public init() {}

    private var filteredPackages: [RemoteExtensionPackage] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAllLangs = selectedLanguage == "all"
        let targetLang = selectedLanguage.lowercased()

        return availablePackages.filter { pkg in
            let matchesLang = isAllLangs || pkg.lang.lowercased() == targetLang
            if query.isEmpty {
                return matchesLang
            }
            return matchesLang && (
                pkg.name.localizedCaseInsensitiveContains(query) ||
                pkg.lang.localizedCaseInsensitiveContains(query)
            )
        }
    }

    public var body: some View {
        List {
            // Repository Sources Section
            Section {
                Button {
                    isShowingAddRepoAlert = true
                } label: {
                    Label("Add Custom Repository", systemImage: "plus.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(YomiTheme.accent)
                }

                if !repos.isEmpty {
                    ForEach(repos) { repo in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name)
                                    .font(.subheadline.bold())
                                Text(repo.url)
                                    .font(.caption2)
                                    .foregroundStyle(YomiTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(repo.sourcesCount) sources")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(YomiTheme.surface)
                                .clipShape(Capsule())
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteRepository(repo)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Installed Repositories (\(repos.count))")
            }

            // Language Filter Pills
            if !availablePackages.isEmpty && availableLanguages.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableLanguages.prefix(12), id: \.self) { lang in
                                Button {
                                    selectedLanguage = lang
                                } label: {
                                    Text(lang.uppercased())
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(selectedLanguage == lang ? YomiTheme.accent : YomiTheme.surface)
                                        .foregroundStyle(selectedLanguage == lang ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Filter by Language")
                }
            }

            // Available Extensions List
            Section {
                if isLoading && availablePackages.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Fetching extensions catalog...")
                            .font(.subheadline)
                            .foregroundStyle(YomiTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else if availablePackages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 36))
                            .foregroundStyle(YomiTheme.textSecondary)
                        Text("No Extensions Loaded")
                            .font(.headline)
                        Text("Enter a repository URL above or pull down to refresh extensions.")
                            .font(.caption)
                            .foregroundStyle(YomiTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if filteredPackages.isEmpty {
                    Text("No extensions matching '\(searchQuery)'")
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textSecondary)
                } else {
                    ForEach(filteredPackages) { pkg in
                        let isInstalled = extensionManager.installedSources.contains(where: { $0.manifest.id == pkg.id })
                        let isInstalling = installingPackageIds.contains(pkg.id)

                        ExtensionPackageRow(
                            pkg: pkg,
                            isInstalled: isInstalled,
                            isInstalling: isInstalling,
                            onInstall: {
                                installPackage(pkg)
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Available Extensions (\(filteredPackages.count))")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .searchable(text: $searchQuery, prompt: "Search extensions by name or source...")
        .refreshable {
            await reloadAll()
        }
        .alert("Add Extension Repository", isPresented: $isShowingAddRepoAlert) {
            TextField("https://raw.githubusercontent.com/.../index.json", text: $newRepoURL)
            Button("Add") {
                addRepository(urlString: newRepoURL)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the HTTPS URL of the repository index. Supports Keiyoushi, Mihon, and Yomi formats.")
        }
        .alert("Repository Error", isPresented: $isShowingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unexpected error occurred while loading the repository.")
        }
        .onAppear {
            loadReposAndPackages()
        }
    }

    private func loadReposAndPackages(forceRefresh: Bool = false) {
        isLoading = true
        Task {
            repos = (try? await repoRepo.getAllRepos()) ?? []
            var packages: [RemoteExtensionPackage] = []

            for repo in repos {
                if let index = try? await repoManager.fetchRepoIndex(from: repo.url, forceRefresh: forceRefresh) {
                    packages.append(contentsOf: index.extensions)
                }
            }

            self.availablePackages = packages

            // Extract unique available languages sorted alphabetically with 'all' first
            let langs = Set(packages.map { $0.lang.lowercased() })
            let sortedLangs = ["all"] + langs.filter { $0 != "all" }.sorted()
            self.availableLanguages = sortedLangs

            self.isLoading = false
        }
    }

    private func reloadAll() async {
        loadReposAndPackages(forceRefresh: true)
    }

    private func addRepository(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newRepoURL = ""
        isLoading = true

        Task {
            do {
                let normalizedUrl = repoManager.normalizeRepoUrl(trimmed)
                let index = try await repoManager.fetchRepoIndex(from: normalizedUrl)
                let repo = ExtensionRepo(
                    name: index.name,
                    url: normalizedUrl,
                    websiteUrl: index.website,
                    sourcesCount: index.extensions.count,
                    lastChecked: Date()
                )
                try await repoRepo.upsertRepo(repo)
                loadReposAndPackages()
            } catch {
                errorMessage = "Could not add repository: \(error.localizedDescription)"
                isShowingErrorAlert = true
                isLoading = false
            }
        }
    }

    private func deleteRepository(_ repo: ExtensionRepo) {
        Task {
            try? await repoRepo.deleteRepo(url: repo.url)
            loadReposAndPackages()
        }
    }

    private func installPackage(_ package: RemoteExtensionPackage) {
        installingPackageIds.insert(package.id)
        Task {
            do {
                _ = try await repoManager.installExtension(package: package)
                extensionManager.reloadInstalledSources()
            } catch {
                errorMessage = "Failed to install \(package.name): \(error.localizedDescription)"
                isShowingErrorAlert = true
            }
            installingPackageIds.remove(package.id)
        }
    }
}

// MARK: - Extension Package Row View

struct ExtensionPackageRow: View {
    let pkg: RemoteExtensionPackage
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: pkg.iconUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fit)
                default:
                    Image(systemName: "puzzlepiece.extension")
                        .font(.title2)
                        .foregroundStyle(YomiTheme.accent)
                }
            }
            .frame(width: 38, height: 38)
            .background(YomiTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(pkg.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(YomiTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(pkg.lang.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(YomiTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("v\(pkg.version)")
                        .font(.caption2)
                        .foregroundStyle(YomiTheme.textSecondary)

                    if pkg.isNsfw {
                        Text("18+")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Spacer()

            if isInstalled {
                Button("Installed") {}
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else if isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 60)
            } else {
                Button("Install") {
                    onInstall()
                }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(YomiTheme.accent)
            }
        }
        .padding(.vertical, 4)
    }
}
