import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit

/// Algorithms for detecting and removing empty whitespace or dark scan borders from manga pages.
public enum AutocropProcessor {
    
    /// Analyzes image pixels and returns a tightly cropped image with empty outer borders removed.
    public static func cropBorders(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width > 20, height > 20 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isBorderPixel(r: UInt8, g: UInt8, b: UInt8) -> Bool {
            let isWhite = r > 240 && g > 240 && b > 240
            let isBlack = r < 15 && g < 15 && b < 15
            return isWhite || isBlack
        }

        func isRowEmpty(_ y: Int) -> Bool {
            let rowOffset = y * bytesPerRow
            for x in stride(from: 0, to: width, by: 4) {
                let offset = rowOffset + (x * bytesPerPixel)
                let r = rawData[offset]
                let g = rawData[offset + 1]
                let b = rawData[offset + 2]
                if !isBorderPixel(r: r, g: g, b: b) {
                    return false
                }
            }
            return true
        }

        func isColEmpty(_ x: Int, top: Int, bottom: Int) -> Bool {
            for y in stride(from: top, to: bottom, by: 4) {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = rawData[offset]
                let g = rawData[offset + 1]
                let b = rawData[offset + 2]
                if !isBorderPixel(r: r, g: g, b: b) {
                    return false
                }
            }
            return true
        }

        var top = 0
        while top < height / 4 && isRowEmpty(top) {
            top += 1
        }

        var bottom = height - 1
        while bottom > (height * 3) / 4 && isRowEmpty(bottom) {
            bottom -= 1
        }

        var left = 0
        while left < width / 4 && isColEmpty(left, top: top, bottom: bottom) {
            left += 1
        }

        var right = width - 1
        while right > (width * 3) / 4 && isColEmpty(right, top: top, bottom: bottom) {
            right -= 1
        }

        let cropWidth = right - left
        let cropHeight = bottom - top

        if cropWidth > width / 2 && cropHeight > height / 2 && (left > 2 || right < width - 3 || top > 2 || bottom < height - 3) {
            let cropRect = CGRect(x: left, y: top, width: cropWidth, height: cropHeight)
            if let croppedCG = cgImage.cropping(to: cropRect) {
                return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
            }
        }

        return image
    }
}
#endif
