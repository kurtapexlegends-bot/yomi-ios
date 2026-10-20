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

public final class ReaderViewController: UIViewController {
    public weak var delegate: ReaderViewControllerDelegate?

    public var pages: [ReaderPage] = [] {
        didSet {
            loadGeneration &+= 1
            pageImages.removeAll()
            loadingIndices.removeAll()
            if isViewLoaded {
                collectionView.reloadData()
            }
        }
    }

    public var viewer: MangaViewer = .defaultViewer {
        didSet {
            guard oldValue != viewer else { return }
            if isViewLoaded {
                configureLayout()
            }
        }
    }

    public var isAutocropEnabled: Bool = false {
        didSet {
            guard oldValue != isAutocropEnabled else { return }
            if isViewLoaded {
                collectionView.reloadData()
            }
        }
    }

    public var tapZoneLayout: TapZoneLayout = .leftRight
    public var customBrightness: CGFloat = 1.0 {
        didSet {
            guard oldValue != customBrightness else { return }
            brightnessOverlay.alpha = max(0, min(0.9, 1.0 - customBrightness))
        }
    }
    public var isInvertColorsEnabled: Bool = false {
        didSet {
            guard oldValue != isInvertColorsEnabled else { return }
            // This property is assigned by the SwiftUI bridge before viewDidLoad; touching
            // collectionView then would trap on a nil implicitly-unwrapped optional.
            guard isViewLoaded else { return }
            applyInvertColors()
        }
    }

    public internal(set) var currentPageIndex: Int = 0

    var collectionView: UICollectionView!
    let brightnessOverlay = UIView()
    var pageImages: [Int: UIImage] = [:]
    var loadingIndices: Set<Int> = []
    /// Incremented whenever `pages` changes so stale async loads cannot write into a new chapter.
    var loadGeneration: Int = 0
    public var source: (any SourceProtocol)?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupCollectionView()
        setupBrightnessOverlay()
        setupGestures()

        // Apply reader settings that may have been assigned before the view existed.
        applyInvertColors()
        brightnessOverlay.alpha = max(0, min(0.9, 1.0 - customBrightness))
    }

    private func applyInvertColors() {
        collectionView.layer.compositingFilter = isInvertColorsEnabled ? "differenceBlendMode" : nil
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
        guard isViewLoaded, let cv = collectionView else { return }

        guard cv.numberOfSections > 0, cv.numberOfItems(inSection: 0) > index else {
            // Collection view has not finished layout yet; schedule on next main loop cycle
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isViewLoaded, let cv = self.collectionView else { return }
                if cv.numberOfSections > 0 && cv.numberOfItems(inSection: 0) > index {
                    let indexPath = IndexPath(item: index, section: 0)
                    let scrollPosition: UICollectionView.ScrollPosition = (self.viewer == .webtoon || self.viewer == .vertical) ? .top : .centeredHorizontally
                    cv.scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
                }
            }
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        let scrollPosition: UICollectionView.ScrollPosition = (viewer == .webtoon || viewer == .vertical) ? .top : .centeredHorizontally
        cv.scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
        delegate?.readerViewController(self, didChangePage: currentPageIndex, totalPages: pages.count)
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        let current = currentPageIndex
        pageImages = pageImages.filter { $0.key == current }
        ImageDownsampler.shared.purgeMemory()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let targetPage = currentPageIndex
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self, self.isViewLoaded, let cv = self.collectionView else { return }
            cv.collectionViewLayout.invalidateLayout()
        }) { [weak self] _ in
            guard let self = self, self.isViewLoaded, let cv = self.collectionView else { return }
            self.scrollToPage(index: targetPage, animated: false)
        }
    }
}
#endif
