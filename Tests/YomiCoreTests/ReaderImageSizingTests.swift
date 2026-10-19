import XCTest
import CoreGraphics
@testable import YomiCore

final class ReaderImageSizingTests: XCTestCase {

    func testStandardPageIsCappedToViewport() {
        let size = ReaderImageSizing.targetPixelSize(
            nativeWidth: 2400,
            nativeHeight: 3600,
            viewport: CGSize(width: 390, height: 844),
            scale: 2.0
        )
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1688 + 1)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testLongWebtoonStripRespectsPixelBudget() {
        // 800 x 30000 strip: previously decoded at ~780 x 29250 (91 MB) per page.
        let size = ReaderImageSizing.targetPixelSize(
            nativeWidth: 800,
            nativeHeight: 30_000,
            viewport: CGSize(width: 390, height: 844),
            scale: 2.0
        )
        let pixels = size.width * size.height
        XCTAssertLessThanOrEqual(pixels, CGFloat(ReaderImageSizing.maximumDecodedPixels))
        // Aspect ratio must be preserved within rounding tolerance.
        XCTAssertEqual(size.height / size.width, 30_000.0 / 800.0, accuracy: 0.1)
        XCTAssertLessThanOrEqual(size.width, 780 + 1)
    }

    func testExtremelyTallStripStaysBounded() {
        let size = ReaderImageSizing.targetPixelSize(
            nativeWidth: 720,
            nativeHeight: 200_000,
            viewport: CGSize(width: 430, height: 932),
            scale: 2.0
        )
        XCTAssertLessThanOrEqual(size.width * size.height, CGFloat(ReaderImageSizing.maximumDecodedPixels) + 1)
        XCTAssertGreaterThan(size.width, 1)
    }

    func testInvalidInputReturnsZero() {
        let size = ReaderImageSizing.targetPixelSize(
            nativeWidth: 0,
            nativeHeight: 1000,
            viewport: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(size, .zero)
    }
}
