import SwiftUI
import YomiCore
import YomiExtensions

public enum AppTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case updates = "Updates"
    case history = "History"
    case browse = "Browse"
    case more = "More"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .updates: return "bolt.fill"
        case .history: return "clock.arrow.circlepath"
        case .browse: return "safari.fill"
        case .more: return "square.grid.2x2.fill"
        }
    }

    public var shortTitle: String {
        switch self {
        case .library: return "Library"
        case .updates: return "Updates"
        case .history: return "History"
        case .browse: return "Browse"
        case .more: return "More"
        }
    }
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
                .tag(AppTab.browse)

            MoreView()
                .tag(AppTab.more)
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            YomiTabBar(selection: $router.selectedTab)
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
                        Image(systemName: tab.iconName)
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
        case .browse: BrowseView()
        case .more: MoreView()
        }
    }
}

// MARK: - Custom tab bar

public struct YomiTabBar: View {
    @Binding public var selection: AppTab

    public init(selection: Binding<AppTab>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(YomiTheme.accentSoft)
                                    .frame(width: 38, height: 26)
                            }
                            Image(systemName: tab.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selection == tab ? YomiTheme.accentStrong : YomiTheme.textTertiary)
                                .symbolEffect(.bounce, value: selection == tab)
                        }
                        .frame(height: 26)

                        Text(tab.shortTitle)
                            .font(.system(size: 9, weight: selection == tab ? .bold : .medium, design: .rounded))
                            .foregroundStyle(selection == tab ? YomiTheme.textPrimary : YomiTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(YomiTheme.background.opacity(0.82))
            }
            .overlay(alignment: .top) {
                Rectangle().fill(YomiTheme.border).frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        )
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
