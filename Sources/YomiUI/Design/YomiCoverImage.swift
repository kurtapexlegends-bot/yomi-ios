import SwiftUI

/// Standardized manga cover renderer with aspect caching, subtle hairline border,
/// and minimalist placeholder state.
public struct YomiCoverImage: View {
    public let urlString: String?
    public let title: String
    public let cornerRadius: CGFloat

    public init(urlString: String?, title: String, cornerRadius: CGFloat = 6) {
        self.urlString = urlString
        self.title = title
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        AsyncImage(url: URL(string: urlString ?? "")) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay(ProgressView().tint(YomiTheme.textTertiary).scaleEffect(0.65))
            @unknown default:
                placeholder
            }
        }
        .background(YomiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 0.5)
        )
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
