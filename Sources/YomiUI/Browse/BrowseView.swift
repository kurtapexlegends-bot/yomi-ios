import SwiftUI
import WebKit
import YomiCore
import YomiExtensions
import YomiDatabase

public struct BrowseView: View {
    @State private var selectedTab: Int = 0 // 0 = Sources, 1 = Extension Store
    @State private var cloudflareSolver = CloudflareSolver.shared

    private let extensionManager = ExtensionManager.shared

    public init() {}

    private var sources: [any SourceProtocol] {
        extensionManager.installedSources
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sources", selection: $selectedTab) {
                    Text("Sources").tag(0)
                    Text("Extension Store").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    SourcesListView(sources: sources)
                } else {
                    ExtensionStoreView()
                }
            }
            .navigationTitle("Sources")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(YomiTheme.accent)
                    }
                }
            }
            .navigationDestination(for: SourceManifest.self) { manifest in
                if let source = extensionManager.getSource(id: manifest.id) {
                    SourceExplorationView(source: source)
                }
            }
        }
    }
}


// MARK: - Sources List

struct SourcesListView: View {
    let sources: [any SourceProtocol]

    var body: some View {
        List {
            Section("Installed Sources (\(sources.count))") {
                ForEach(sources, id: \.manifest.id) { source in
                    NavigationLink(value: source.manifest) {
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: source.manifest.iconUrl ?? "")) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fit)
                                default:
                                    Image(systemName: "globe")
                                        .font(.title2)
                                        .foregroundStyle(YomiTheme.accent)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .background(YomiTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(source.manifest.name)
                                        .font(.headline)
                                        .foregroundStyle(YomiTheme.textPrimary)

                                    if source.manifest.id == MangaPillSource.sourceId || source.manifest.id == MangaDexSource.sourceId {
                                        Text("Native")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundStyle(Color.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }

                                HStack(spacing: 6) {
                                    Text(source.manifest.lang.uppercased())
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(YomiTheme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text("v\(source.manifest.version)")
                                        .font(.caption)
                                        .foregroundStyle(YomiTheme.textSecondary)

                                    if source.manifest.id == MangaPillSource.sourceId {
                                        Text("• Full Chapters")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
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
    }
}

// MARK: - Cloudflare Solver Sheet

public struct CloudflareSolverSheet: View {
    @State private var solver = CloudflareSolver.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Please solve the Cloudflare verification challenge to continue.")
                    .font(.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .padding(.vertical, 8)

                if let url = solver.activeChallengeUrl {
                    CloudflareWebView(url: url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .navigationTitle("Cloudflare Verification")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        solver.cancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        solver.userDidCompleteChallenge()
                    }
                    .bold()
                }
            }
        }
    }
}

#if canImport(UIKit)
public struct CloudflareWebView: UIViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> WKWebView {
        if let existing = CloudflareSolver.shared.activeWebView {
            return existing
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let bounds = UIScreen.main.bounds
        let initialFrame = bounds.width > 0 ? bounds : CGRect(x: 0, y: 0, width: 390, height: 844)
        let webView = WKWebView(frame: initialFrame, configuration: config)
        webView.customUserAgent = NetworkBridge.defaultUserAgent
        webView.navigationDelegate = CloudflareSolver.shared
        CloudflareSolver.shared.activeWebView = webView
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        webView.load(req)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
public struct CloudflareWebView: View {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var body: some View {
        Text("Cloudflare Solver")
    }
}
#endif
