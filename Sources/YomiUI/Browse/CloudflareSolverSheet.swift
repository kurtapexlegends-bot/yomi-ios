import SwiftUI
import YomiCore
import YomiExtensions
#if canImport(UIKit)
import WebKit
#endif

/// Interactive Cloudflare verification sheet.
///
/// The page is loaded at the challenged host's origin, uses the shared default data store so
/// clearance cookies immediately become available to the WebKit transport, and keeps the sheet
/// open until the user completes verification or explicitly cancels.
public struct CloudflareSolverSheet: View {
    @State private var solver = CloudflareSolver.shared
    @State private var isLoading: Bool = true
    @State private var reloadToken: Int = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                VStack(spacing: 0) {
                    statusCard

                    if let url = solver.activeChallengeUrl {
                        CloudflareWebView(url: url, isLoading: $isLoading)
                            .id("\(url.absoluteString)-\(reloadToken)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    } else {
                        Spacer()
                        ProgressView().tint(YomiTheme.accentStrong)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Verification")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        solver.cancel()
                    }
                    .foregroundStyle(YomiTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        solver.userDidCompleteChallenge()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(YomiTheme.accentStrong)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YomiTheme.accentStrong)
                    .frame(width: 38, height: 38)
                    .background(YomiTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloudflare verification")
                        .font(YomiFont.cardTitle)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text(solver.statusMessage ?? "Complete the verification below. Yomi will detect the clearance cookie automatically.")
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                if isLoading {
                    ProgressView().tint(YomiTheme.accentStrong).scaleEffect(0.65)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(YomiTheme.textTertiary)
                }
                Text(isLoading ? "Loading challenge page…" : "Verification cookies stay on this device")
                    .font(YomiFont.micro)
                    .foregroundStyle(YomiTheme.textTertiary)

                Spacer()

                Button {
                    reloadToken += 1
                    isLoading = true
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                        .font(YomiFont.micro)
                        .foregroundStyle(YomiTheme.accentStrong)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#if canImport(UIKit)
public struct CloudflareWebView: UIViewRepresentable {
    public let url: URL
    @Binding public var isLoading: Bool

    public init(url: URL, isLoading: Binding<Bool> = .constant(false)) {
        self.url = url
        self._isLoading = isLoading
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var progressObservation: NSKeyValueObservation?
        var loadingBinding: Binding<Bool>?

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loadingBinding?.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadingBinding?.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadingBinding?.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadingBinding?.wrappedValue = false
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let bounds = UIScreen.main.bounds
        let initialFrame = bounds.width > 0 ? bounds : CGRect(x: 0, y: 0, width: 390, height: 844)
        let webView = WKWebView(frame: initialFrame, configuration: config)
        webView.customUserAgent = NetworkBridge.defaultUserAgent
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        CloudflareSolver.shared.activeWebView = webView

        context.coordinator.loadingBinding = $isLoading
        context.coordinator.progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak coordinator = context.coordinator] _, change in
            guard let progress = change.newValue else { return }
            Task { @MainActor in
                coordinator?.loadingBinding?.wrappedValue = progress < 1.0
            }
        }

        load(url, in: webView, coordinator: context.coordinator)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.loadingBinding = $isLoading
        if context.coordinator.loadedURL != url {
            load(url, in: uiView, coordinator: context.coordinator)
        }
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.progressObservation?.invalidate()
        coordinator.progressObservation = nil
        uiView.stopLoading()
        if CloudflareSolver.shared.activeWebView === uiView {
            CloudflareSolver.shared.activeWebView = nil
        }
    }

    private func load(_ url: URL, in webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedURL = url
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        CloudflareSolver.shared.activeWebView = webView
        webView.load(request)
    }
}
#else
public struct CloudflareWebView: View {
    public let url: URL

    public init(url: URL, isLoading: Binding<Bool> = .constant(false)) {
        self.url = url
    }

    public var body: some View {
        Text("Cloudflare verification requires iOS.")
    }
}
#endif
