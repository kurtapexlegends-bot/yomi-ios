import SwiftUI
import YomiCore

// MARK: - Chapter list sheet

struct ReaderChapterListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [Chapter]
    let currentChapterId: Int64?
    let onSelect: (Chapter) -> Void

    @State private var searchText: String = ""

    private var filteredChapters: [Chapter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || ($0.scanlator?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ReaderPalette.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 6) {
                        searchField

                        ForEach(filteredChapters, id: \.stableId) { chapter in
                            chapterRow(chapter)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Chapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ReaderPalette.violetBright)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            TextField("Find a chapter", text: $searchText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.38))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(ReaderPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 5)
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.id == currentChapterId
        return Button {
            onSelect(chapter)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "play.circle.fill" : chapter.read ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isCurrent ? ReaderPalette.violetBright : chapter.read ? ReaderPalette.green : .white.opacity(0.28))

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.displayTitle)
                        .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.84))
                        .lineLimit(1)
                    if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                        Text(scanlator)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if chapter.bookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(ReaderPalette.gold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrent ? ReaderPalette.violet.opacity(0.20) : ReaderPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent ? ReaderPalette.violet.opacity(0.50) : .white.opacity(0.05), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
