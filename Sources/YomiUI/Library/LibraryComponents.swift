import SwiftUI
import YomiCore

public struct ReaderRequest: Identifiable {
    public let id = UUID()
    public let manga: Manga
    public let chapter: Chapter

    public init(manga: Manga, chapter: Chapter) {
        self.manga = manga
        self.chapter = chapter
    }
}

public enum LibrarySort: String, CaseIterable {
    case title = "Title"
    case recentlyAdded = "Recently Added"
    case lastUpdated = "Last Updated"
    case lastRead = "Last Read"
    case mostUnread = "Most Unread"
}

public enum LibraryFilter: String, CaseIterable {
    case all = "All Titles"
    case unread = "Unread"
    case downloaded = "Downloaded"
    case completed = "Completed"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .unread: return "circle.fill"
        case .downloaded: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        }
    }
}

public struct LibraryFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let sort: LibrarySort
    public let filter: LibraryFilter
    public let onSelectSort: (LibrarySort) -> Void
    public let onSelectFilter: (LibraryFilter) -> Void

    public init(
        sort: LibrarySort,
        filter: LibraryFilter,
        onSelectSort: @escaping (LibrarySort) -> Void,
        onSelectFilter: @escaping (LibraryFilter) -> Void
    ) {
        self.sort = sort
        self.filter = filter
        self.onSelectSort = onSelectSort
        self.onSelectFilter = onSelectFilter
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section("Sort by") {
                            ForEach(LibrarySort.allCases, id: \.self) { option in
                                selectionRow(
                                    title: option.rawValue,
                                    icon: "arrow.up.arrow.down",
                                    selected: sort == option
                                ) {
                                    onSelectSort(option)
                                }
                            }
                        }

                        section("Filter") {
                            ForEach(LibraryFilter.allCases, id: \.self) { option in
                                selectionRow(
                                    title: option.title,
                                    icon: option.icon,
                                    selected: filter == option
                                ) {
                                    onSelectFilter(option)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Library View")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(YomiFont.micro)
                .tracking(1.2)
                .foregroundStyle(YomiTheme.textTertiary)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 14)
                .background(YomiTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusSmall, style: .continuous)
                        .stroke(YomiTheme.border, lineWidth: 0.5)
                )
        }
    }

    private func selectionRow(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? YomiTheme.accentStrong : YomiTheme.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .font(YomiFont.body)
                    .foregroundStyle(YomiTheme.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YomiTheme.accentStrong)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
