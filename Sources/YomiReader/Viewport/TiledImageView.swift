import Foundation
import UIKit
import CoreGraphics

/// CATiledLayer-backed view that draws image chunks on demand to eliminate large bitmap RAM spikes.
public final class TiledImageView: UIView {
    public var image: UIImage? {
        didSet {
            setNeedsDisplay()
        }
    }

    public override class var layerClass: AnyClass {
        CATiledLayer.self
    }

    public var tiledLayer: CATiledLayer {
        layer as! CATiledLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
        tiledLayer.levelsOfDetail = 3
        tiledLayer.levelsOfDetailBias = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ rect: CGRect) {
        guard let image = image, let cgImage = image.cgImage else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        // Flip coordinate system for CGImage
        context.translateBy(x: 0, y: bounds.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }
}

/// A smooth zoomable scroll view containing a manga page with double-tap zoom and pinch-to-zoom gestures.
public final class ZoomablePageScrollView: UIScrollView, UIScrollViewDelegate {
    public let imageView = UIImageView()
    private var doubleTapGesture: UITapGestureRecognizer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        delegate = self
        minimumZoomScale = 1.0
        maximumZoomScale = 4.0
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        self.doubleTapGesture = doubleTap
    }

    public func configure(with image: UIImage?) {
        imageView.image = image
        setZoomScale(1.0, animated: false)
        updateImageFrame()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1.0 {
            updateImageFrame()
        }
    }

    private func updateImageFrame() {
        guard let img = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        let aspect = img.size.width / img.size.height
        let viewAspect = bounds.width / bounds.height

        var targetWidth: CGFloat
        var targetHeight: CGFloat

        if aspect > viewAspect {
            targetWidth = bounds.width
            targetHeight = bounds.width / aspect
        } else {
            targetHeight = bounds.height
            targetWidth = bounds.height * aspect
        }

        let originX = max(0, (bounds.width - targetWidth) / 2.0)
        let originY = max(0, (bounds.height - targetHeight) / 2.0)

        imageView.frame = CGRect(x: originX, y: originY, width: targetWidth, height: targetHeight)
        contentSize = bounds.size
    }

    // MARK: - UIScrollViewDelegate

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((bounds.height - contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(x: contentSize.width * 0.5 + offsetX, y: contentSize.height * 0.5 + offsetY)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.0 {
            setZoomScale(1.0, animated: true)
        } else {
            let pointInView = gesture.location(in: imageView)
            let newZoomScale = 2.5
            let w = bounds.size.width / newZoomScale
            let h = bounds.size.height / newZoomScale
            let x = pointInView.x - (w / 2.0)
            let y = pointInView.y - (h / 2.0)
            zoom(to: CGRect(x: x, y: y, width: w, height: h), animated: true)
        }
    }
}
