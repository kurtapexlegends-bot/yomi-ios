import SwiftUI

/// Platform shims for modifiers that only exist on iOS.
///
/// YomiUI is also compiled for macOS by `swift test` even though the shipping app is iOS-only.
/// Keeping the platform differences here prevents every screen from duplicating conditional
/// compilation and keeps the iOS behavior unchanged.
public extension View {
    /// Presents the reader full-screen on iOS and as a regular sheet on macOS test builds.
    @ViewBuilder
    func yomiFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    /// Hides the navigation bar on iOS. The macOS test build keeps its native toolbar.
    @ViewBuilder
    func yomiNavigationBarHidden() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
