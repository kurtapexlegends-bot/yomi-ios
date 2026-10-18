import Foundation
import CoreGraphics
import YomiCore

#if canImport(UIKit)
import UIKit

public protocol ReaderViewControllerDelegate: AnyObject {
    func readerViewController(_ controller: ReaderViewController, didChangePage pageIndex: Int, totalPages: Int)
    func readerViewControllerDidToggleHUD(_ controller: ReaderViewController)
    func readerViewControllerRequestsNextChapter(_ controller: ReaderViewController)
    func readerViewControllerRequestsPreviousChapter(_ controller: ReaderViewController)
}

public final class ReaderViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public weak var delegate: ReaderViewControllerDelegate?

    public var pages: [ReaderPage] = [] {
        didSet {
            pageImages.removeAll()
            collectionView.reloadData()
        }
    }

    public var viewer: MangaViewer = .defaultViewer {
        didSet {
            configureLayout()
        }
    }

    public var isAutocropEnabled: Bool = false {
        didSet { collectionView.reloadData() }
    }

    public var tapZoneLayout: TapZoneLayout = .leftRight
    public var customBrightness: CGFloat = 1.0 {
        didSet {
            brightnessOverlay.alpha = max(0, min(0.9, 1.0 - customBrightness))
        }
    }
    public var isInvertColorsEnabled: Bool = false {
        didSet {
            collectionView.layer.compositingFilter = isInvertColorsEnabled ? "differenceBlendMode" : nil
        }
    }

    public private(set) var currentPageIndex: Int = 0

    private var collectionView: UICollectionView!
    private let brightnessOverlay = UIView()
    private var pageImages: [Int: UIImage] = [:]
    private var loadingIndices: Set<Int> = []
    public var source: (any SourceProtocol)?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCollectionView()
        setupBrightnessOverlay()
        setupGestures()
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(ReaderCollectionViewCell.self, forCellWithReuseIdentifier: ReaderCollectionViewCell.reuseIdentifier)
        
        view.addSubview(collectionView)
        configureLayout()
    }

    private func setupBrightnessOverlay() {
        brightnessOverlay.frame = view.bounds
        brightnessOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        brightnessOverlay.backgroundColor = .black
        brightnessOverlay.alpha = 0.0
        brightnessOverlay.isUserInteractionEnabled = false
        view.addSubview(brightnessOverlay)
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
    }

    public func configureLayout() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }

        switch viewer {
        case .webtoon:
            layout.scrollDirection = .vertical
            collectionView.isPagingEnabled = false
            collectionView.semanticContentAttribute = .unspecified

        case .rightToLeft:
            layout.scrollDirection = .horizontal
            collectionView.isPagingEnabled = true
            collectionView.semanticContentAttribute = .forceRightToLeft

        case .leftToRight:
            layout.scrollDirection = .horizontal
            collectionView.isPagingEnabled = true
            collectionView.semanticContentAttribute = .forceLeftToRight

        case .continuousHorizontal:
            layout.scrollDirection = .horizontal
            collectionView.isPagingEnabled = false
            collectionView.semanticContentAttribute = .unspecified

        case .defaultViewer, .vertical:
            layout.scrollDirection = .vertical
            collectionView.isPagingEnabled = true
            collectionView.semanticContentAttribute = .unspecified
        }

        collectionView.reloadData()
    }

    // MARK: - Navigation

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let isRTL = viewer == .rightToLeft
        let action = TapZoneDetector.action(for: location, in: view.bounds, layout: tapZoneLayout, isRTL: isRTL)

        switch action {
        case .previousPage:
            goToPreviousPage()
        case .nextPage:
            goToNextPage()
        case .toggleMenu:
            delegate?.readerViewControllerDidToggleHUD(self)
        }
    }

    public func goToNextPage() {
        if currentPageIndex < pages.count - 1 {
            scrollToPage(index: currentPageIndex + 1, animated: true)
        } else {
            delegate?.readerViewControllerRequestsNextChapter(self)
        }
    }

    public func goToPreviousPage() {
        if currentPageIndex > 0 {
            scrollToPage(index: currentPageIndex - 1, animated: true)
        } else {
            delegate?.readerViewControllerRequestsPreviousChapter(self)
        }
    }

    public func scrollToPage(index: Int, animated: Bool) {
        guard index >= 0 && index < pages.count else { return }
        currentPageIndex = index
        let indexPath = IndexPath(item: index, section: 0)
        let scrollPosition: UICollectionView.ScrollPosition = (viewer == .webtoon || viewer == .vertical) ? .top : .centeredHorizontally
        collectionView.scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
        delegate?.readerViewController(self, didChangePage: currentPageIndex, totalPages: pages.count)
    }

    // MARK: - UICollectionViewDataSource

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pages.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReaderCollectionViewCell.reuseIdentifier, for: indexPath) as! ReaderCollectionViewCell
        let page = pages[indexPath.item]
        let cachedImage = pageImages[indexPath.item]
        let isLoading = cachedImage == nil && loadingIndices.contains(indexPath.item)
        let isWebtoon = viewer == .webtoon

        cell.configure(
            page: page,
            image: cachedImage,
            isLoading: isLoading,
            isWebtoon: isWebtoon,
            autocrop: isAutocropEnabled
        )

        cell.onRetry = { [weak self] in
            self?.loadPageImage(at: indexPath.item)
        }

        if cachedImage == nil && !loadingIndices.contains(indexPath.item) {
            loadPageImage(at: indexPath.item)
        }

        // Prefetch adjacent pages
        prefetchAdjacentPages(around: indexPath.item)

        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let height = collectionView.bounds.height

        if viewer == .webtoon {
            if let image = pageImages[indexPath.item] {
                let aspect = image.size.height / image.size.width
                return CGSize(width: width, height: width * aspect)
            }
            return CGSize(width: width, height: height * 0.8) // Placeholder height until loaded
        }

        return CGSize(width: width, height: height)
    }

    // MARK: - Prefetching & Image Loading

    private func loadPageImage(at index: Int) {
        guard index >= 0 && index < pages.count else { return }
        guard let src = source else { return }

        loadingIndices.insert(index)
        let page = pages[index]

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let data: Data
                if let localPath = page.localPath, FileManager.default.fileExists(atPath: localPath) {
                    data = try Data(contentsOf: URL(fileURLWithPath: localPath))
                } else {
                    data = try await src.getImageData(page: page)
                }

                if let downsampled = ImageDownsampler.shared.downsample(data: data, to: self.view.bounds.size) {
                    self.pageImages[index] = downsampled
                }
            } catch {
                print("[ReaderViewController] Failed to load image at page \(index): \(error)")
            }
            self.loadingIndices.remove(index)
            self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }

    private func prefetchAdjacentPages(around index: Int) {
        let prefetchIndices = [index + 1, index + 2, index - 1]
        for idx in prefetchIndices {
            if idx >= 0 && idx < pages.count && pageImages[idx] == nil && !loadingIndices.contains(idx) {
                loadPageImage(at: idx)
            }
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visiblePoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        if let indexPath = collectionView.indexPathForItem(at: visiblePoint), indexPath.item != currentPageIndex {
            currentPageIndex = indexPath.item
            delegate?.readerViewController(self, didChangePage: currentPageIndex, totalPages: pages.count)
        }
    }
}
#endif
