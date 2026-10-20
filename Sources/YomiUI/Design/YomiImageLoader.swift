import SwiftUI
import ImageIO
import YomiExtensions
#if canImport(UIKit)
import UIKit
public typealias YomiImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias YomiImage = NSImage
#endif

/// High-performance, memory-efficient image cache and loader with automatic downsampling
/// and referer header support for manga CDN hosts (e.g. MangaPill, Mangakakalot, MangaDex).
public final class YomiImageCache: @unchecked Sendable {
    public static let shared = YomiImageCache()

    #if canImport(UIKit)
    private let cache = NSCache<NSString, UIImage>()
    #endif
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 150 * 1024 * 1024,
            diskPath: "yomi_cover_cache"
        )
        self.session = URLSession(configuration: config)

        #if canImport(UIKit)
        cache.countLimit = 150
        cache.totalCostLimit = 40 * 1024 * 1024 // 40 MB max in RAM

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
        #endif
    }

    #if canImport(UIKit)
    public func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    public func insertImage(_ image: UIImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    #endif

    public func loadImage(from urlString: String, targetSize: CGSize = CGSize(width: 320, height: 440)) async -> YomiImage? {
        #if canImport(UIKit)
        let cacheKey = "\(urlString)-\(Int(targetSize.width))x\(Int(targetSize.height))"
        if let cached = image(for: cacheKey) {
            return cached
        }

        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        // Determine referer header required by CDNs (MangaPill, Mangakakalot, etc.)
        let host = url.host?.lowercased() ?? ""
        if host.contains("readdetectiveconan.com") || host.contains("mangapill.com") {
            request.setValue("https://mangapill.com/", forHTTPHeaderField: "Referer")
        } else if host.contains("mangakakalot") {
            request.setValue("https://www.mangakakalot.gg/", forHTTPHeaderField: "Referer")
        } else if let scheme = url.scheme, !host.isEmpty {
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
        }

        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/webp,image/avif,image/jpeg,image/png,*/*;q=0.8", forHTTPHeaderField: "Accept")

        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        do {
            var rawData: Data?
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 400 {
                rawData = data
            } else {
                // If direct URLSession was rejected by CDN / Cloudflare, try WebKit fallback
                rawData = await WebViewFetchService.shared.fetchData(request)
            }

            guard let finalData = rawData, let downsampled = Self.downsample(imageData: finalData, to: targetSize) else {
                return nil
            }

            let cost = Int(targetSize.width * targetSize.height * 4)
            insertImage(downsampled, for: cacheKey, cost: cost)
            return downsampled
        } catch {
            // Attempt WebKit transport before giving up on network error
            if let webKitData = await WebViewFetchService.shared.fetchData(request),
               let downsampled = Self.downsample(imageData: webKitData, to: targetSize) {
                let cost = Int(targetSize.width * targetSize.height * 4)
                insertImage(downsampled, for: cacheKey, cost: cost)
                return downsampled
            }
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    public static func downsample(imageData: Data, to targetSize: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(imageData as CFData, options as CFDictionary) else {
            return UIImage(data: imageData)
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: imageData)
        }

        return UIImage(cgImage: thumbnail)
    }
    #endif
}
