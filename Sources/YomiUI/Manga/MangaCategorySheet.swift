import SwiftUI
import YomiCore
import YomiDatabase
import YomiSync

/// Category assignment sheet with biometric protection for locked shelves.
struct MangaCategorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let mangaId: Int64
    let onSaved: () -> Void

    @State private var categories: [YomiCategory] = []
    @State private var selectedIds: Set<Int64> = []
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var newCategoryName: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    private let categoryRepo = CategoryRepository()
    private let privacyManager = PrivacyManager.shared
    private let biometrics = BiometricSecurityManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                YomiBackground(showsGlow: false)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        YomiCard(padding: 13) {
                            Text("Choose the shelves this title belongs to. Locked categories require authentication before changing.")
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.textSecondary)
                                .lineSpacing(2)
                        }

                        if isLoading {
                            ProgressView().tint(YomiTheme.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else if categories.isEmpty {
                            YomiEmptyState(
                                icon: "folder.badge.plus",
                                title: "No Categories Yet",
                                message: "Create a shelf below to organize your library."
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(categories) { category in
                                    categoryRow(category)
                                }
                            }
                        }

                        createCategoryCard

                        if let errorMessage {
                            Text(errorMessage)
                                .font(YomiFont.caption)
                                .foregroundStyle(YomiTheme.danger)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Categories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(YomiTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().tint(YomiTheme.accentStrong).scaleEffect(0.7)
                        } else {
                            Text("Save")
                        }
                    }
                    .foregroundStyle(YomiTheme.accentStrong)
                    .disabled(isSaving || isLoading)
                }
            }
            .task { await load() }
        }
    }

    private func categoryRow(_ category: YomiCategory) -> some View {
        let isSelected = category.id.map { selectedIds.contains($0) } ?? false
        return Button {
            Task { await toggle(category) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? YomiTheme.accentStrong : YomiTheme.textTertiary)

                Text(category.name)
                    .font(YomiFont.body.weight(.semibold))
                    .foregroundStyle(YomiTheme.textPrimary)

                Spacer()

                if category.isLocked {
                    Image(systemName: privacyManager.isCategoryUnlocked(category) ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(YomiTheme.warning)
                }
            }
            .padding(13)
            .background(YomiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? YomiTheme.accent.opacity(0.5) : YomiTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var createCategoryCard: some View {
        YomiCard(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                Text("New category")
                    .font(YomiFont.cardTitle)
                    .foregroundStyle(YomiTheme.textPrimary)

                HStack(spacing: 8) {
                    TextField("e.g. Favorites", text: $newCategoryName)
                        .font(YomiFont.caption)
                        .foregroundStyle(YomiTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(YomiTheme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(YomiTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        createCategory()
                    } label: {
                        if isCreating {
                            ProgressView().tint(.white).scaleEffect(0.65)
                        } else {
                            Text("Create")
                        }
                    }
                    .buttonStyle(YomiPrimaryButtonStyle())
                    .disabled(isCreating || newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        categories = (try? await categoryRepo.getAllCategories()) ?? []
        selectedIds = Set((try? await categoryRepo.getCategoryIds(forMangaId: mangaId)) ?? [])
        isLoading = false
    }

    private func toggle(_ category: YomiCategory) async {
        guard let id = category.id else { return }

        if category.isLocked && !privacyManager.isCategoryUnlocked(category) {
            let success = await biometrics.requestUnlock(reason: "Unlock \(category.name)")
            guard success else { return }
            privacyManager.unlockCategory(category)
        }

        withAnimation(.easeOut(duration: 0.16)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else {
                selectedIds.insert(id)
            }
        }
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreating else { return }
        isCreating = true

        Task {
            do {
                let category = try await categoryRepo.createCategory(name: name)
                categories = (try? await categoryRepo.getAllCategories()) ?? categories
                if let id = category.id {
                    // Select it locally; the sheet's Save action commits the assignment so Cancel
                    // still leaves the manga's existing shelves untouched.
                    selectedIds.insert(id)
                }
                newCategoryName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await categoryRepo.setMangaCategories(mangaId: mangaId, categoryIds: Array(selectedIds))
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
