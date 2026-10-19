import Foundation
import CoreGraphics
import YomiCore

#if canImport(UIKit)
import UIKit

// MARK: - UICollectionViewDataSource & FlowLayout

extension ReaderViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pages.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ReaderCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as! ReaderCollectionViewCell

        guard indexPath.item < pages.count else { return cell }

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

        prefetchAdjacentPages(around: indexPath.item)
        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let baseBounds = collectionView.bounds.width > 0 ? collectionView.bounds : (view.bounds.width > 0 ? view.bounds : UIScreen.main.bounds)
        let width = max(baseBounds.width, 1)
        let height = max(baseBounds.height, 1)

        guard indexPath.item < pages.count else {
            return CGSize(width: width, height: height)
        }

        if viewer == .webtoon {
            if let image = pageImages[indexPath.item], image.size.width > 0 {
                let aspect = image.size.height / image.size.width
                return CGSize(width: width, height: max(1, width * aspect))
            }
            return CGSize(width: width, height: max(1, height * 0.8))
        }

        return CGSize(width: width, height: height)
    }

    // MARK: - Prefetching & Image Loading

    func loadPageImage(at index: Int) {
        guard index >= 0 && index < pages.count else { return }
        guard let src = source else { return }

        let generation = loadGeneration
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

                // The chapter may have changed while the image was downloading.
                guard self.loadGeneration == generation else { return }

                let targetSize = self.view.bounds.width > 0 ? self.view.bounds.size : UIScreen.main.bounds.size
                let downsampled: UIImage? = autoreleasepool {
                    ImageDownsampler.shared.downsample(data: data, to: targetSize)
                }
                if let downsampled = downsampled {
                    self.pageImages[index] = downsampled
                }
            } catch {
                print("[ReaderViewController] Failed to load image at page \(index): \(error)")
            }

            guard self.loadGeneration == generation else { return }
            self.loadingIndices.remove(index)

            // Safely update cell if visible without risking an invalid reloadItems crash
            if self.isViewLoaded, let cv = self.collectionView {
                let indexPath = IndexPath(item: index, section: 0)
                if cv.numberOfSections > 0 && cv.numberOfItems(inSection: 0) > index {
                    if let cell = cv.cellForItem(at: indexPath) as? ReaderCollectionViewCell, index < self.pages.count {
                        cell.configure(
                            page: self.pages[index],
                            image: self.pageImages[index],
                            isLoading: false,
                            isWebtoon: self.viewer == .webtoon,
                            autocrop: self.isAutocropEnabled
                        )
                        if self.viewer == .webtoon {
                            cv.collectionViewLayout.invalidateLayout()
                        }
                    }
                }
            }
        }
    }

    func prefetchAdjacentPages(around index: Int) {
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
            pruneDistantPages(around: currentPageIndex)
            delegate?.readerViewController(self, didChangePage: currentPageIndex, totalPages: pages.count)
        }
    }

    /// Releases decoded images outside the active visible window (±3 pages) to prevent GPU memory saturation
    func pruneDistantPages(around currentIndex: Int) {
        let keepWindow = 3
        let minIndex = max(0, currentIndex - keepWindow)
        let maxIndex = min(pages.count - 1, currentIndex + keepWindow)

        let keysToPrune = pageImages.keys.filter { $0 < minIndex || $0 > maxIndex }
        for key in keysToPrune {
            pageImages.removeValue(forKey: key)
        }
    }
}
#endif
