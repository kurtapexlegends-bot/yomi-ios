import SwiftUI
import YomiCore
import YomiExtensions

public enum AppTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case updates = "Updates"
    case history = "History"
    case sources = "Sources"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .updates: return "bell.fill"
        case .history: return "clock.arrow.circlepath"
        case .sources: return "globe"
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
    @State private var cloudflareSolver = CloudflareSolver.shared

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

                    UpdatesView()
                        .tabItem {
                            Label("Updates", systemImage: "bell.fill")
                        }
                        .tag(AppTab.updates)

                    HistoryView()
                        .tabItem {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .tag(AppTab.history)

                    BrowseView()
                        .tabItem {
                            Label("Sources", systemImage: "globe")
                        }
                        .tag(AppTab.sources)

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
        .sheet(isPresented: $cloudflareSolver.isPresentingSolverSheet) {
            CloudflareSolverSheet()
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .library: LibraryView()
        case .updates: UpdatesView()
        case .history: HistoryView()
        case .sources: BrowseView()
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
