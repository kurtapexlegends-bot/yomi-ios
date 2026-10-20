import SwiftUI
import YomiCore
import YomiDatabase
import YomiDownload
import YomiExtensions

public struct MoreView: View {
    @State private var privacyManager = PrivacyManager.shared
    @State private var biometricManager = BiometricSecurityManager.shared
    @State private var extensionManager = ExtensionManager.shared
    @State private var router = AppRouter.shared

    @State private var libraryCount: Int = 0
    @State private var chaptersRead: Int = 0
    @State private var downloadedBytes: Int64 = 0
    @State private var historyCount: Int = 0
    @State private var isLoadingStats: Bool = true

    private let mangaRepo = MangaRepository()
    private let chapterRepo = ChapterRepository()
    private let historyRepo = HistoryRepository()
    private let downloadManager = DownloadManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                        profileCard
                        quickActions
                        settingsShortcuts
                        privacySection
                        footer
                    }
                    .padding(.horizontal, YomiTheme.contentPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .yomiNavigationBarHidden()
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .downloads: DownloadsView()
                case .extensions: ExtensionStoreView()
                case .categories: CategoryManagerView()
                case .statistics: StatisticsView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
            .task { await loadStats() }
        }
    }

    private var header: some View {
        YomiScreenHeader(title: "More", subtitle: "Your library, sources, and reading setup") {
            Button {
                router.openBrowse()
            } label: {
                Image(systemName: "safari.fill")
            }
            .buttonStyle(YomiIconButtonStyle())
        }
    }

    private var profileCard: some View {
        YomiCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        YomiEyebrow("YOMI READER")
                        Text(privacyManager.isIncognitoMode ? "Private session" : "Local-first reading")
                            .font(YomiFont.sectionTitle)
                            .foregroundStyle(YomiTheme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(YomiTheme.accentStrong)
                        .frame(width: 44, height: 44)
                        .background(YomiTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                HStack(spacing: 12) {
                    YomiStatBadge(
                        icon: "books.vertical.fill",
                        value: isLoadingStats ? "—" : "\(libraryCount)",
                        label: "Titles"
                    )
                    YomiStatBadge(
                        icon: "checkmark.circle.fill",
                        value: isLoadingStats ? "—" : "\(chaptersRead)",
                        label: "Read",
                        tint: YomiTheme.success
                    )
                    YomiStatBadge(
                        icon: "arrow.down.circle.fill",
                        value: isLoadingStats ? "—" : ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file),
                        label: "Offline",
                        tint: YomiTheme.warning
                    )
                }

                HStack(spacing: 8) {
                    YomiTag("\(extensionManager.installedSources.count) sources", tint: YomiTheme.accentStrong)
                    if historyCount > 0 {
                        YomiTag("\(historyCount) history entries", tint: YomiTheme.textSecondary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            YomiSectionHeader("Workspace")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                quickAction(
                    title: "Downloads",
                    subtitle: "Offline chapters",
                    icon: "arrow.down.circle.fill",
                    tint: YomiTheme.success,
                    destination: .downloads
                )
                quickAction(
                    title: "Extensions",
                    subtitle: "Add new sources",
                    icon: "puzzlepiece.extension.fill",
                    tint: YomiTheme.accentStrong,
                    destination: .extensions
                )
                quickAction(
                    title: "Categories",
                    subtitle: "Organize titles",
                    icon: "folder.fill",
                    tint: YomiTheme.warning,
                    destination: .categories
                )
                quickAction(
                    title: "Statistics",
                    subtitle: "Reading footprint",
                    icon: "chart.bar.fill",
                    tint: YomiTheme.unreadBadge,
                    destination: .statistics
                )
            }
        }
    }

    private func quickAction(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        destination: MoreDestination
    ) -> some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(subtitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var settingsShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            YomiSectionHeader("Settings")

            VStack(spacing: 0) {
                settingsRow(
                    icon: "slider.horizontal.3",
                    tint: YomiTheme.accentStrong,
                    title: "Reader & Appearance",
                    subtitle: "Modes, brightness, tap zones, theme",
                    destination: .settings
                )
                Divider().overlay(YomiTheme.border).padding(.leading, 54)
                settingsRow(
                    icon: "globe",
                    tint: YomiTheme.unreadBadge,
                    title: "Sources & Repositories",
                    subtitle: "\(extensionManager.installedSources.count) installed sources",
                    destination: .extensions
                )
                Divider().overlay(YomiTheme.border).padding(.leading, 54)
                settingsRow(
                    icon: "info.circle.fill",
                    tint: YomiTheme.textSecondary,
                    title: "About Yomi",
                    subtitle: "Version, architecture, credits",
                    destination: .about
                )
            }
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                    .stroke(YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
        }
    }

    private func settingsRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        destination: MoreDestination
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(YomiFont.body.weight(.semibold))
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(subtitle)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(YomiTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YomiSectionHeader("Privacy")

            YomiCard(padding: 0) {
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "eye.slash.fill",
                        tint: YomiTheme.accentStrong,
                        title: "Incognito mode",
                        isOn: Binding(
                            get: { privacyManager.isIncognitoMode },
                            set: { _ in privacyManager.toggleIncognito() }
                        )
                    )
                    Divider().overlay(YomiTheme.border).padding(.leading, 54)
                    toggleRow(
                        icon: "lock.shield.fill",
                        tint: YomiTheme.danger,
                        title: "Biometric app lock",
                        isOn: $biometricManager.isAppLockEnabled
                    )
                }
            }
        }
    }

    private func toggleRow(icon: String, tint: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Toggle(title, isOn: isOn)
                .font(YomiFont.body.weight(.semibold))
                .tint(YomiTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("YOMI")
                .font(YomiFont.micro)
                .tracking(3)
                .foregroundStyle(YomiTheme.textTertiary)
            Text("Designed for quiet, uninterrupted reading.")
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func loadStats() async {
        async let mangas = try? mangaRepo.getLibraryMangas()
        async let progress = try? chapterRepo.getLibraryProgress()
        async let history = try? historyRepo.getHistory(limit: 1)

        let loadedMangas = await mangas ?? []
        let loadedProgress = await progress ?? [:]
        let loadedHistory = await history ?? []

        await MainActor.run {
            libraryCount = loadedMangas.count
            chaptersRead = loadedProgress.values.reduce(0) { $0 + $1.readChapters }
            downloadedBytes = downloadManager.totalDownloadedBytes()
            historyCount = loadedHistory.count
            isLoadingStats = false
        }
    }
}

enum MoreDestination: Hashable {
    case downloads
    case extensions
    case categories
    case statistics
    case settings
    case about
}
