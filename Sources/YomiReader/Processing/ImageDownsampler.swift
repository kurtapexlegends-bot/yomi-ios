import Foundation
import CoreGraphics
import ImageIO

#if canImport(UIKit)
import UIKit

/// High-performance image decoding and thumbnail generation using ImageIO sub-sampling.
public final class ImageDownsampler: @unchecked Sendable {
    public static let shared = ImageDownsampler()

    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        memoryCache.totalCostLimit = 150 * 1024 * 1024 // 150 MB memory budget
        memoryCache.countLimit = 60
    }

    /// Downsamples raw image data to target bounding point size before memory decoding.
    public func downsample(data: Data, to pointSize: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let cacheKey = "\(data.count)_\(Int(pointSize.width))x\(Int(pointSize.height))" as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            downsampleOptions as CFDictionary
        ) else {
            return nil
        }

        let image = UIImage(cgImage: downsampledImage)
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    /// Clears cached thumbnails under memory pressure.
    public func purgeMemory() {
        memoryCache.removeAllObjects()
    }
}
#else
public final class ImageDownsampler: @unchecked Sendable {
    public static let shared = ImageDownsampler()
    public func purgeMemory() {}
}
#endif
