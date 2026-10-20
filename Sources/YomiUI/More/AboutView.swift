import SwiftUI
import YomiCore

public struct AboutView: View {
    public init() {}

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    public var body: some View {
        ZStack {
            YomiBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    brandCard
                    principlesCard
                    technicalCard
                    footer
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var brandCard: some View {
        YomiCard(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(YomiTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("YOMI")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Text("A native reader for comics and manga, built around the page.")
                        .font(YomiFont.body)
                        .foregroundStyle(YomiTheme.textSecondary)
                        .lineSpacing(3)
                }

                HStack(spacing: 8) {
                    YomiTag("iOS 17+", tint: YomiTheme.accentStrong)
                    YomiTag(version, tint: YomiTheme.textSecondary)
                    YomiTag("Local-first", tint: YomiTheme.success)
                }
            }
        }
    }

    private var principlesCard: some View {
        YomiCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Principles")
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                aboutRow(
                    icon: "bolt.fill",
                    tint: YomiTheme.accentStrong,
                    title: "Fast by default",
                    detail: "The reader uses native image downsampling, tiled rendering, and a bounded memory window."
                )
                aboutRow(
                    icon: "lock.shield.fill",
                    tint: YomiTheme.success,
                    title: "Private by design",
                    detail: "Library, history, and progress stay on device. Incognito mode stops history and tracker writes."
                )
                aboutRow(
                    icon: "puzzlepiece.extension.fill",
                    tint: YomiTheme.warning,
                    title: "Extensible sources",
                    detail: "Community scrapers run inside an isolated JavaScriptCore sandbox with explicit native bridges."
                )
                aboutRow(
                    icon: "books.vertical.fill",
                    tint: YomiTheme.unreadBadge,
                    title: "Yours to keep",
                    detail: "Downloaded chapters are stored as open .cbz archives and can be read entirely offline."
                )
            }
        }
    }

    private var technicalCard: some View {
        YomiCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Technical")
                    .font(YomiFont.sectionTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                infoRow(label: "Bundle", value: "com.yomiapp.reader")
                Divider().overlay(YomiTheme.border)
                infoRow(label: "Architecture", value: "SwiftUI · UIKit viewport · GRDB")
                Divider().overlay(YomiTheme.border)
                infoRow(label: "Reader", value: "CATiledLayer · ImageIO downsampling")
                Divider().overlay(YomiTheme.border)
                infoRow(label: "Extensions", value: "JavaScriptCore sandbox")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Text("Designed for the page, not the feed.")
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textTertiary)
            Text("読み")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(YomiTheme.accentStrong.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func aboutRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                Text(detail)
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textSecondary)
            Spacer()
            Text(value)
                .font(YomiFont.caption)
                .foregroundStyle(YomiTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
