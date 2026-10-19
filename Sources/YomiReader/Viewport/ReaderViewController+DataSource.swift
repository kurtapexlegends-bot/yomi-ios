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
        let width = collectionView.bounds.width
        let height = collectionView.bounds.height

        if viewer == .webtoon {
            if let image = pageImages[indexPath.item] {
                let aspect = image.size.height / image.size.width
                return CGSize(width: width, height: width * aspect)
            }
            return CGSize(width: width, height: height * 0.8)
        }

        return CGSize(width: width, height: height)
    }

    // MARK: - Prefetching & Image Loading

    func loadPageImage(at index: Int) {
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

    /// Releases decoded images outside active visible window (±6 pages) to prevent GPU memory saturation
    func pruneDistantPages(around currentIndex: Int) {
        let keepWindow = 6
        let minIndex = max(0, currentIndex - keepWindow)
        let maxIndex = min(pages.count - 1, currentIndex + keepWindow)

        let keysToPrune = pageImages.keys.filter { $0 < minIndex || $0 > maxIndex }
        for key in keysToPrune {
            pageImages.removeValue(forKey: key)
        }
    }
}
#endif
