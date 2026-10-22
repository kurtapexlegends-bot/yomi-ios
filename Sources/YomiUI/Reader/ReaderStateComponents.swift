import SwiftUI
import YomiCore

/// Polished glassmorphic empty state view for chapters that could not load pages.
public struct ReaderEmptyStateView: View {
    public let chapterTitle: String
    public let errorMessage: String?
    public let isMangaDexSource: Bool
    public let onRetry: () -> Void
    public let onNextChapter: () -> Void
    public let onSwitchSource: () -> Void
    public let onClose: () -> Void

    public init(
        chapterTitle: String,
        errorMessage: String?,
        isMangaDexSource: Bool,
        onRetry: @escaping () -> Void,
        onNextChapter: @escaping () -> Void,
        onSwitchSource: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.chapterTitle = chapterTitle
        self.errorMessage = errorMessage
        self.isMangaDexSource = isMangaDexSource
        self.onRetry = onRetry
        self.onNextChapter = onNextChapter
        self.onSwitchSource = onSwitchSource
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(YomiTheme.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(YomiTheme.accent)
            }

            VStack(spacing: 8) {
                Text("No Pages Available")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(errorMessage ?? "The source did not return hosted pages for \(chapterTitle). It may be temporarily offline or restricted.")
                    .font(.subheadline)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(YomiTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if isMangaDexSource {
                        Button(action: onSwitchSource) {
                            Label("Try MangaPill", systemImage: "arrow.triangle.swap")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.green.opacity(0.85))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onNextChapter) {
                            Label("Next Chapter", systemImage: "forward.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.white.opacity(0.12))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Close Reader", action: onClose)
                    .font(.subheadline)
                    .foregroundStyle(YomiTheme.textTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
    }
}

/// Minimal, elegant HUD loading indicator.
public struct ReaderLoadingStateView: View {
    public let chapterTitle: String

    public init(chapterTitle: String) {
        self.chapterTitle = chapterTitle
    }

    public var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(YomiTheme.accent)
                .scaleEffect(1.2)

            Text("Loading \(chapterTitle)...")
                .font(.footnote.weight(.medium))
                .foregroundStyle(YomiTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
    }
}
