import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Standardized manga cover renderer with downsampling, custom CDN referer support,
/// in-memory caching, and minimalist placeholder state.
public struct YomiCoverImage: View {
    public let urlString: String?
    public let title: String
    public let cornerRadius: CGFloat

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    @State private var isLoading: Bool = false
    #endif

    public init(urlString: String?, title: String, cornerRadius: CGFloat = 6) {
        self.urlString = urlString
        self.title = title
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if isLoading {
                placeholder
                    .overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.65))
            } else {
                placeholder
            }
            #else
            AsyncImage(url: URL(string: urlString ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    placeholder.overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.65))
                @unknown default:
                    placeholder
                }
            }
            #endif
        }
        .background(YomiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
        #if canImport(UIKit)
        .task(id: urlString) {
            guard let urlString = urlString, !urlString.isEmpty else {
                loadedImage = nil
                return
            }
            if let cached = YomiImageCache.shared.image(for: "\(urlString)-240x340") {
                loadedImage = cached
                return
            }
            isLoading = true
            let img = await YomiImageCache.shared.loadImage(
                from: urlString,
                targetSize: CGSize(width: 240, height: 340)
            )
            withAnimation(.easeIn(duration: 0.15)) {
                loadedImage = img
                isLoading = false
            }
        }
        #endif
    }

    private var placeholder: some View {
        ZStack {
            YomiTheme.elevatedSurface
            Image(systemName: "book.closed")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(YomiTheme.textTertiary)
        }
    }
}
