import SwiftUI
import YomiCore
import YomiDatabase

public struct CategoryManagerView: View {
    @State private var categories: [YomiCategory] = []
    @State private var newCategoryName: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    @State private var categoryToRename: YomiCategory?
    @State private var renameText: String = ""
    @State private var isRenaming: Bool = false

    @State private var categoryToDelete: YomiCategory?
    @State private var isConfirmingDelete: Bool = false

    private let categoryRepo = CategoryRepository()

    public init() {}

    public var body: some View {
        ZStack {
            YomiBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    YomiScreenHeader(
                        title: "Categories",
                        subtitle: "Build shelves that match how you read"
                    )

                    createCard

                    if isLoading {
                        ProgressView()
                            .tint(YomiTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else if categories.isEmpty {
                        YomiEmptyState(
                            icon: "folder",
                            title: "No Categories Yet",
                            message: "Create a category to group favorites, ongoing series, or anything else."
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(categories) { category in
                                categoryRow(category)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(YomiFont.caption)
                            .foregroundStyle(YomiTheme.danger)
                    }
                }
                .padding(.horizontal, YomiTheme.contentPadding)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Categories")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadCategories() }
        .alert("Rename Category", isPresented: $isRenaming) {
            TextField("Category name", text: $renameText)
            Button("Save") { renameCategory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a short, recognizable name.")
        }
        .confirmationDialog(
            "Delete \(categoryToDelete?.name ?? "Category")?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) { deleteCategory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Manga in this category stay in your library. Only the category assignment is removed.")
        }
    }

    private var createCard: some View {
        YomiCard(padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YomiTheme.accentStrong)
                    .frame(width: 34, height: 34)
                    .background(YomiTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("New category name", text: $newCategoryName)
                    .font(YomiFont.body)
                    .foregroundStyle(YomiTheme.textPrimary)
                    .submitLabel(.done)
                    .onSubmit { createCategory() }

                Button("Add") { createCategory() }
                    .font(YomiFont.caption.weight(.bold))
                    .foregroundStyle(canCreate ? YomiTheme.accentStrong : YomiTheme.textTertiary)
                    .disabled(!canCreate)
            }
        }
    }

    private func categoryRow(_ category: YomiCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.isLocked ? "lock.fill" : "folder.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(category.isLocked ? YomiTheme.warning : YomiTheme.accentStrong)
                .frame(width: 34, height: 34)
                .background(
                    (category.isLocked ? YomiTheme.warning : YomiTheme.accentStrong).opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)
                Text(category.isLocked ? "Locked with biometrics" : "Visible in library")
                    .font(YomiFont.caption)
                    .foregroundStyle(YomiTheme.textSecondary)
            }

            Spacer()

            Menu {
                Button {
                    categoryToRename = category
                    renameText = category.name
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    toggleLock(category)
                } label: {
                    Label(category.isLocked ? "Remove Lock" : "Lock Category", systemImage: category.isLocked ? "lock.open" : "lock")
                }

                Button(role: .destructive) {
                    categoryToDelete = category
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(YomiTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(YomiTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(13)
        .background(YomiTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous)
                .stroke(YomiTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: YomiTheme.cornerRadiusMedium, style: .continuous))
    }

    private var canCreate: Bool {
        !newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadCategories() async {
        isLoading = true
        do {
            categories = try await categoryRepo.getAllCategories()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await categoryRepo.createCategory(name: name)
                newCategoryName = ""
                await loadCategories()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameCategory() {
        guard var category = categoryToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        category.name = name
        Task {
            do {
                try await categoryRepo.updateCategory(category)
                await loadCategories()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleLock(_ category: YomiCategory) {
        var updated = category
        updated.isLocked.toggle()
        Task {
            do {
                try await categoryRepo.updateCategory(updated)
                await loadCategories()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCategory() {
        guard let category = categoryToDelete, let id = category.id else { return }
        Task {
            do {
                try await categoryRepo.deleteCategory(id: id)
                categoryToDelete = nil
                await loadCategories()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
