import Foundation
import CoreGraphics
import YomiCore

#if canImport(UIKit)
import UIKit

public final class ReaderCollectionViewCell: UICollectionViewCell {
    public static let reuseIdentifier = "ReaderCollectionViewCell"

    public let zoomScrollView = ZoomablePageScrollView()
    public let webtoonImageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let pageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    public var onRetry: (() -> Void)?
    private var isWebtoonMode: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = .black
        contentView.backgroundColor = .black

        // Webtoon image view (seamless top-to-bottom stitching)
        webtoonImageView.contentMode = .scaleAspectFill
        webtoonImageView.clipsToBounds = true
        webtoonImageView.isHidden = true
        contentView.addSubview(webtoonImageView)

        // Paged zoom scroll view
        zoomScrollView.isHidden = false
        contentView.addSubview(zoomScrollView)

        // Spinner
        spinner.color = .white
        spinner.hidesWhenStopped = true
        contentView.addSubview(spinner)

        // Page number badge
        pageLabel.textColor = .white.withAlphaComponent(0.6)
        pageLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        pageLabel.textAlignment = .center
        pageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        pageLabel.layer.cornerRadius = 8
        pageLabel.clipsToBounds = true
        contentView.addSubview(pageLabel)

        // Retry button
        retryButton.setTitle("Tap to Retry", for: .normal)
        retryButton.setTitleColor(.systemBlue, for: .normal)
        retryButton.isHidden = true
        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
        contentView.addSubview(retryButton)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        zoomScrollView.frame = contentView.bounds
        webtoonImageView.frame = contentView.bounds
        spinner.center = contentView.center
        retryButton.frame = CGRect(x: (contentView.bounds.width - 140) / 2, y: (contentView.bounds.height - 40) / 2, width: 140, height: 40)
        pageLabel.frame = CGRect(x: contentView.bounds.width - 60, y: contentView.bounds.height - 35, width: 50, height: 24)
    }

    public func configure(
        page: ReaderPage,
        image: UIImage?,
        isLoading: Bool,
        isWebtoon: Bool,
        autocrop: Bool
    ) {
        self.isWebtoonMode = isWebtoon
        pageLabel.text = "\(page.index + 1)"

        if isLoading {
            spinner.startAnimating()
            retryButton.isHidden = true
            zoomScrollView.configure(with: nil)
            webtoonImageView.image = nil
        } else if let rawImage = image {
            spinner.stopAnimating()
            retryButton.isHidden = true

            let finalImage = autocrop ? AutocropProcessor.cropBorders(from: rawImage) : rawImage

            if isWebtoon {
                zoomScrollView.isHidden = true
                webtoonImageView.isHidden = false
                webtoonImageView.image = finalImage
            } else {
                zoomScrollView.isHidden = false
                webtoonImageView.isHidden = true
                zoomScrollView.configure(with: finalImage)
            }
        } else {
            spinner.stopAnimating()
            retryButton.isHidden = false
            zoomScrollView.configure(with: nil)
            webtoonImageView.image = nil
        }
    }

    @objc private func didTapRetry() {
        onRetry?()
    }
}
#endif
