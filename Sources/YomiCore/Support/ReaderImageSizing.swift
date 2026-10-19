import Foundation
import CoreGraphics

/// Computes safe decode sizes for reader pages so long webtoon strips can never
/// allocate unbounded bitmaps (a major out-of-memory crash source on device).
public enum ReaderImageSizing {
    /// Hard ceiling of decoded pixels per page (~32 MB RGBA).
    public static let maximumDecodedPixels: Int = 8_000_000

    /// Returns the target pixel size for an image of the given native pixel dimensions.
    ///
    /// - Normal pages keep at most the viewport's longest side at the requested scale.
    /// - Tall webtoon strips keep their aspect ratio but are clamped to ``maximumDecodedPixels``.
    public static func targetPixelSize(
        nativeWidth: CGFloat,
        nativeHeight: CGFloat,
        viewport: CGSize,
        scale: CGFloat = 2.0
    ) -> CGSize {
        guard nativeWidth > 0, nativeHeight > 0, viewport.width > 0, viewport.height > 0 else {
            return .zero
        }

        let aspect = nativeHeight / nativeWidth
        let viewportLongSide = max(viewport.width, viewport.height) * max(1.0, scale)

        var width: CGFloat
        var height: CGFloat

        if aspect <= 1.8 {
            // Standard manga page: cap the longest side to the viewport at scale.
            let longestNativeSide = max(nativeWidth, nativeHeight)
            let scaling = min(1.0, viewportLongSide / longestNativeSide)
            width = nativeWidth * scaling
            height = nativeHeight * scaling
        } else {
            // Webtoon long strip: preserve width at viewport scale, keep full height,
            // then clamp the total pixel count below.
            width = min(nativeWidth, viewport.width * max(1.0, scale))
            height = width * aspect
        }

        let pixelBudget = CGFloat(maximumDecodedPixels)
        if width * height > pixelBudget {
            let factor = sqrt(pixelBudget / (width * height))
            width *= factor
            height *= factor
        }

        return CGSize(width: max(1, floor(width)), height: max(1, floor(height)))
    }
}
