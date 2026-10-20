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
        case .library: return "books.vertical"
        case .updates: return "bell"
        case .history: return "clock"
        case .sources: return "safari"
        case .settings: return "gearshape"
        }
    }

    public var selectedIconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .updates: return "bell.fill"
        case .history: return "clock.fill"
        case .sources: return "safari.fill"
        case .settings: return "gearshape.fill"
        }
    }

    public var shortTitle: String { rawValue }

    // Backwards-compatible aliases
    public static var browse: AppTab { .sources }
    public static var more: AppTab { .settings }
}

/// Root application view switching between the iPhone tab experience and iPadOS sidebar.
public struct AppRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var router = AppRouter.shared
    @State private var selectedTab: AppTab? = .library
    @State private var biometricManager = BiometricSecurityManager.shared
    @State private var privacyManager = PrivacyManager.shared
    @State private var cloudflareSolver = CloudflareSolver.shared

    public init() {}

    public var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }

            if biometricManager.isAppLockEnabled && !biometricManager.isUnlocked {
                BiometricLockShieldView()
                    .transition(.opacity)
            }

            if privacyManager.isPrivacyShieldActive {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .tint(YomiTheme.accent)
        .onChange(of: router.selectedTab) { _, tab in
            selectedTab = tab
        }
        .onChange(of: selectedTab) { _, tab in
            if let tab, router.selectedTab != tab {
                router.selectedTab = tab
            }
        }
        .sheet(isPresented: $cloudflareSolver.isPresentingSolverSheet) {
            CloudflareSolverSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - iPhone

    private var iPhoneLayout: some View {
        TabView(selection: $router.selectedTab) {
            LibraryView()
                .tag(AppTab.library)

            UpdatesView()
                .tag(AppTab.updates)

            HistoryView()
                .tag(AppTab.history)

            BrowseView()
                .tag(AppTab.sources)

            SettingsView()
                .tag(AppTab.settings)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            YomiTabBar(selection: $router.selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    // MARK: - iPad

    private var iPadLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label {
                        Text(tab.rawValue)
                            .font(YomiFont.body.weight(.semibold))
                    } icon: {
                        Image(systemName: selectedTab == tab ? tab.selectedIconName : tab.iconName)
                            .foregroundStyle(selectedTab == tab ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    }
                }
                .listRowBackground(
                    selectedTab == tab
                        ? YomiTheme.accentSoft
                        : Color.clear
                )
            }
            .scrollContentBackground(.hidden)
            .background(YomiBackground(showsGlow: false))
            .navigationTitle("Yomi")
        } detail: {
            tabContent(for: selectedTab ?? .library)
        }
        .tint(YomiTheme.accent)
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

// MARK: - Floating tab bar

public struct YomiTabBar: View {
    @Binding public var selection: AppTab

    public init(selection: Binding<AppTab>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isSelected ? tab.selectedIconName : tab.iconName)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? YomiTheme.textPrimary : YomiTheme.textTertiary)
                            .frame(height: 22)

                        Text(tab.shortTitle)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? YomiTheme.textPrimary : YomiTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            }
                        }
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.85))
            }
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
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
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(YomiTheme.accentStrong)
                    .frame(width: 104, height: 104)
                    .background(YomiTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                Text("Yomi is Locked")
                    .font(YomiFont.screenTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                Text("Authenticate to open your library, history, and downloaded chapters.")
                    .font(YomiFont.body)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button {
                    Task {
                        _ = await biometricManager.requestUnlock()
                    }
                } label: {
                    Label("Unlock with \(biometricManager.availableBiometricType().title)", systemImage: "faceid")
                }
                .buttonStyle(YomiPrimaryButtonStyle())
                .padding(.top, 10)
            }
        }
    }
}
