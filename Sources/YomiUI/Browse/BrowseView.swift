import SwiftUI
import WebKit
import YomiCore
import YomiExtensions
import YomiDatabase

public struct BrowseView: View {
    @State private var selectedTab: Int = 0 // 0 = Sources, 1 = Extension Store
    @State private var sources: [any SourceProtocol] = []
    @State private var selectedSourceForExploration: (any SourceProtocol)?
    @State private var cloudflareSolver = CloudflareSolver.shared

    private let extensionManager = ExtensionManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Browse", selection: $selectedTab) {
                    Text("Sources").tag(0)
                    Text("Extension Store").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    SourcesListView(sources: sources) { source in
                        selectedSourceForExploration = source
                    }
                } else {
                    ExtensionStoreView()
                }
            }
            .navigationTitle("Browse")
            .onAppear {
                sources = extensionManager.installedSources
            }
            .navigationDestination(item: $selectedSourceForExploration) { source in
                SourceExplorationView(source: source)
            }
            .sheet(isPresented: $cloudflareSolver.isPresentingSolverSheet) {
                CloudflareSolverSheet()
            }
        }
    }
}

// MARK: - Sources List

struct SourcesListView: View {
    let sources: [any SourceProtocol]
    let onSelect: (any SourceProtocol) -> Void

    var body: some View {
        List {
            Section("Installed Sources") {
                ForEach(sources, id: \.manifest.id) { source in
                    Button {
                        onSelect(source)
                    } label: {
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
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.manifest.name)
                                    .font(.headline)
                                    .foregroundStyle(YomiTheme.textPrimary)
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
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(YomiTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Cloudflare Solver Sheet

struct CloudflareSolverSheet: View {
    @State private var solver = CloudflareSolver.shared

    var body: some View {
        NavigationStack {
            VStack {
                Text("Please solve the Cloudflare verification challenge to continue.")
                    .font(.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .padding(.top, 8)

                if let url = solver.activeChallengeUrl {
                    CloudflareWebView(url: url)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Cloudflare Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        solver.cancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        solver.userDidCompleteChallenge()
                    }
                    .bold()
                }
            }
        }
    }
}

struct CloudflareWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = NetworkBridge.defaultUserAgent
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        webView.load(req)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
