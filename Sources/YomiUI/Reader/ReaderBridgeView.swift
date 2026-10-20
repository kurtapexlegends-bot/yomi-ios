import SwiftUI
import YomiCore
import YomiReader

#if canImport(UIKit)
import UIKit

// MARK: - UIViewControllerRepresentable Bridge

struct ReaderBridgeView: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let source: (any SourceProtocol)?
    let viewer: MangaViewer
    let isAutocropEnabled: Bool
    let isInvertColorsEnabled: Bool
    let customBrightness: CGFloat
    let tapZoneLayout: TapZoneLayout
    @Binding var currentPageIndex: Int

    let onToggleHUD: () -> Void
    let onRequestNextChapter: () -> Void
    let onRequestPreviousChapter: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ReaderViewController {
        let vc = ReaderViewController()
        vc.source = source
        vc.delegate = context.coordinator
        vc.pages = pages
        vc.viewer = viewer
        vc.isAutocropEnabled = isAutocropEnabled
        vc.isInvertColorsEnabled = isInvertColorsEnabled
        vc.customBrightness = customBrightness
        vc.tapZoneLayout = tapZoneLayout
        return vc
    }

    func updateUIViewController(_ uiViewController: ReaderViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.source = source
        if uiViewController.viewer != viewer {
            uiViewController.viewer = viewer
        }
        if uiViewController.isAutocropEnabled != isAutocropEnabled {
            uiViewController.isAutocropEnabled = isAutocropEnabled
        }
        if uiViewController.isInvertColorsEnabled != isInvertColorsEnabled {
            uiViewController.isInvertColorsEnabled = isInvertColorsEnabled
        }
        if uiViewController.customBrightness != customBrightness {
            uiViewController.customBrightness = customBrightness
        }
        uiViewController.tapZoneLayout = tapZoneLayout

        // Synchronize page list when chapter updates
        if uiViewController.pages.map(\.url) != pages.map(\.url) {
            uiViewController.pages = pages
            if !pages.isEmpty && uiViewController.isViewLoaded {
                uiViewController.scrollToPage(index: min(currentPageIndex, pages.count - 1), animated: false)
            }
        } else if uiViewController.currentPageIndex != currentPageIndex {
            // Synchronize HUD scrubber scrub position
            if !pages.isEmpty && uiViewController.isViewLoaded {
                uiViewController.scrollToPage(index: min(currentPageIndex, pages.count - 1), animated: false)
            }
        }
    }

    final class Coordinator: NSObject, ReaderViewControllerDelegate {
        var parent: ReaderBridgeView

        init(_ parent: ReaderBridgeView) {
            self.parent = parent
        }

        func readerViewController(_ controller: ReaderViewController, didChangePage pageIndex: Int, totalPages: Int) {
            DispatchQueue.main.async {
                self.parent.currentPageIndex = pageIndex
            }
        }

        func readerViewControllerDidToggleHUD(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onToggleHUD()
            }
        }

        func readerViewControllerRequestsNextChapter(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onRequestNextChapter()
            }
        }

        func readerViewControllerRequestsPreviousChapter(_ controller: ReaderViewController) {
            DispatchQueue.main.async {
                self.parent.onRequestPreviousChapter()
            }
        }
    }
}
#endif
