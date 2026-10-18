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
    @State private var errorMessage: String?

    private let repoRepo = ExtensionRepoRepository()
    private let repoManager = RepoManager.shared
    private let extensionManager = ExtensionManager.shared

    public init() {}

    public var body: some View {
        List {
            // Repositories Header
            Section {
                Button {
                    isShowingAddRepoAlert = true
                } label: {
                    Label("Add Extension Repository", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(YomiTheme.accent)
                }
            } header: {
                Text("Repository Sources")
            } footer: {
                Text("Paste a community repository URL to access community extensions.")
            }

            // Available Extensions List
            Section("Available Extensions") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Fetching extensions...")
                        Spacer()
                    }
                } else if availablePackages.isEmpty {
                    Text("No external extensions found. Add a repository above.")
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textSecondary)
                } else {
                    ForEach(availablePackages) { pkg in
                        let isInstalled = extensionManager.installedSources.contains(where: { $0.manifest.id == pkg.id })

                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: pkg.iconUrl ?? "")) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fit)
                                default:
                                    Image(systemName: "puzzlepiece.extension")
                                        .font(.title2)
                                        .foregroundStyle(YomiTheme.textSecondary)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(pkg.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(pkg.lang.uppercased())
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(YomiTheme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text("v\(pkg.version)")
                                        .font(.caption)
                                        .foregroundStyle(YomiTheme.textSecondary)
                                }
                            }

                            Spacer()

                            if isInstalled {
                                Button("Installed") {}
                                    .font(.caption.bold())
                                    .buttonStyle(.bordered)
                                    .disabled(true)
                            } else {
                                Button("Install") {
                                    installPackage(pkg)
                                }
                                .font(.caption.bold())
                                .buttonStyle(.borderedProminent)
                                .tint(YomiTheme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .alert("Add Extension Repository", isPresented: $isShowingAddRepoAlert) {
            TextField("https://raw.githubusercontent.com/.../index.json", text: $newRepoURL)
            Button("Add") {
                addRepository()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the raw HTTPS URL of the repository index.json file.")
        }
        .onAppear {
            loadReposAndPackages()
        }
    }

    private func loadReposAndPackages() {
        isLoading = true
        Task {
            repos = (try? await repoRepo.getAllRepos()) ?? []
            var packages: [RemoteExtensionPackage] = []

            for repo in repos {
                if let index = try? await repoManager.fetchRepoIndex(from: repo.url) {
                    packages.append(contentsOf: index.extensions)
                }
            }

            self.availablePackages = packages
            self.isLoading = false
        }
    }

    private func addRepository() {
        guard !newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = newRepoURL
        newRepoURL = ""

        isLoading = true
        Task {
            do {
                let index = try await repoManager.fetchRepoIndex(from: url)
                let repo = ExtensionRepo(
                    name: index.name,
                    url: url,
                    websiteUrl: index.website,
                    sourcesCount: index.extensions.count,
                    lastChecked: Date()
                )
                try await repoRepo.upsertRepo(repo)
                loadReposAndPackages()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func installPackage(_ package: RemoteExtensionPackage) {
        Task {
            do {
                _ = try await repoManager.installExtension(package: package)
                extensionManager.reloadInstalledSources()
            } catch {
                print("[ExtensionStore] Failed to install package: \(error)")
            }
        }
    }
}
