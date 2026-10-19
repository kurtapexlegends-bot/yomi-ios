import SwiftUI
import YomiCore

public enum AppTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case browse = "Browse"
    case downloads = "Downloads"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .browse: return "safari.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Root application view switching between iPhone TabView and iPadOS NavigationSplitView.
public struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: AppTab? = .library
    @State private var biometricManager = BiometricSecurityManager.shared
    @State private var privacyManager = PrivacyManager.shared

    public init() {}

    public var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                // iPadOS Multi-Column Navigation Split View
                NavigationSplitView {
                    List(AppTab.allCases, selection: $selectedTab) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.rawValue, systemImage: tab.iconName)
                        }
                    }
                    .navigationTitle("Yomi")
                } detail: {
                    tabContent(for: selectedTab ?? .library)
                }
            } else {
                // iPhone Native Tab Bar
                TabView(selection: Binding(
                    get: { selectedTab ?? .library },
                    set: { selectedTab = $0 }
                )) {
                    LibraryView()
                        .tabItem {
                            Label("Library", systemImage: "books.vertical.fill")
                        }
                        .tag(AppTab.library)

                    BrowseView()
                        .tabItem {
                            Label("Browse", systemImage: "safari.fill")
                        }
                        .tag(AppTab.browse)

                    DownloadsView()
                        .tabItem {
                            Label("Downloads", systemImage: "arrow.down.circle.fill")
                        }
                        .tag(AppTab.downloads)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .tag(AppTab.settings)
                }
            }

            // Biometric App Lock Shield
            if biometricManager.isAppLockEnabled && !biometricManager.isUnlocked {
                BiometricLockShieldView()
                    .transition(.opacity)
            }

            // Multitasking Snapshot Privacy Blur
            if privacyManager.isPrivacyShieldActive {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library: LibraryView()
        case .browse: BrowseView()
        case .downloads: DownloadsView()
        case .settings: SettingsView()
        }
    }
}

/// Overlay shield presented when the application is locked behind biometrics.
struct BiometricLockShieldView: View {
    private let biometricManager = BiometricSecurityManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(YomiTheme.accent)

                Text("Yomi is Locked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Biometric authentication is required to access your library.")
                    .font(.subheadline)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task {
                        _ = await biometricManager.requestUnlock()
                    }
                } label: {
                    Label("Unlock with \(biometricManager.availableBiometricType().title)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(YomiTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 16)
            }
        }
    }
}
