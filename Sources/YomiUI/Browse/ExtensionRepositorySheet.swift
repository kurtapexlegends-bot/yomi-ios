import SwiftUI
import YomiCore
import YomiDatabase
import YomiExtensions

/// Add/remove extension repositories without exposing JSON URLs in the main store.
public struct ExtensionRepositorySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var repos: [ExtensionRepo] = []
    @State private var newRepoURL: String = ""
    @State private var isWorking: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var repoToDelete: ExtensionRepo?

    private let repoRepo = ExtensionRepoRepository()
    private let repoManager = RepoManager.shared
    public let onChanged: () -> Void

    public init(onChanged: @escaping () -> Void) {
        self.onChanged = onChanged
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        YomiCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Add repository")
                                    .font(YomiFont.cardTitle)
                                    .foregroundStyle(YomiTheme.textPrimary)
                                Text("Paste a repository index URL. Yomi normalizes GitHub links and legacy index.min.json addresses.")
                                    .font(YomiFont.caption)
                                    .foregroundStyle(YomiTheme.textSecondary)
                                    .lineSpacing(2)

                                HStack(spacing: 8) {
                                    TextField("https://example.com/index.json", text: $newRepoURL)
                                        .font(YomiFont.caption)
                                        .foregroundStyle(YomiTheme.textPrimary)
                                        .padding(.horizontal, 11)
                                        .frame(height: 40)
                                        .background(YomiTheme.background)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(YomiTheme.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .autocorrectionDisabled()

                                    Button {
                                        addRepository()
                                    } label: {
                                        if isWorking {
                                            ProgressView().tint(.white).scaleEffect(0.7)
                                        } else {
                                            Text("Add")
                                        }
                                    }
                                    .buttonStyle(YomiPrimaryButtonStyle())
                                    .disabled(isWorking || newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.danger)
                        }

                        YomiSectionHeader("Repositories", subtitle: "\(repos.count) configured")

                        if isLoading {
                            ProgressView().tint(YomiTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 24)
                        } else {
                            VStack(spacing: 9) {
                                ForEach(repos) { repo in
                                    repoRow(repo)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Repositories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .task { await loadRepos() }
            .confirmationDialog(
                "Remove \(repoToDelete?.name ?? "repository")?",
                isPresented: Binding(
                    get: { repoToDelete != nil },
                    set: { if !$0 { repoToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Repository", role: .destructive) { deleteRepo() }
                Button("Cancel", role: .cancel) { repoToDelete = nil }
            } message: {
                Text("Installed extensions stay on device. The store will stop listing this repository's catalog.")
            }
        }
    }

    private func repoRow(_ repo: ExtensionRepo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YomiTheme.accentStrong)
                .frame(width: 38, height: 38)
                .background(YomiTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .lineLimit(1)
                    if repo.url.contains("keiyoushi") {
                        YomiTag("DEFAULT", tint: YomiTheme.success)
                    }
                }
                Text(URL(string: repo.url)?.host ?? repo.url)
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineLimit(1)
                if repo.sourcesCount > 0 {
                    Text("\(repo.sourcesCount) extensions indexed")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.textTertiary)
                }
            }

            Spacer(minLength: 2)

            Button(role: .destructive) {
                repoToDelete = repo
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(YomiTheme.danger)
                    .frame(width: 34, height: 34)
                    .background(YomiTheme.danger.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
    }

    private func loadRepos() async {
        isLoading = true
        repos = (try? await repoRepo.getAllRepos()) ?? []
        isLoading = false
    }

    private func addRepository() {
        let raw = newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                let normalized = repoManager.normalizeRepoUrl(raw)
                let index = try await repoManager.fetchRepoIndex(from: normalized, forceRefresh: true)
                let repo = ExtensionRepo(
                    name: index.name,
                    url: normalized,
                    websiteUrl: index.website,
                    sourcesCount: index.extensions.count,
                    lastChecked: Date()
                )
                try await repoRepo.upsertRepo(repo)
                newRepoURL = ""
                await loadRepos()
                onChanged()
            } catch {
                errorMessage = "Could not add repository: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func deleteRepo() {
        guard let repo = repoToDelete else { return }
        Task {
            try? await repoRepo.deleteRepo(url: repo.url)
            repoToDelete = nil
            await loadRepos()
            onChanged()
        }
    }
}
