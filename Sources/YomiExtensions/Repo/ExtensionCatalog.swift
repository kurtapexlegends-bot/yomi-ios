import Foundation

/// A store row representing one extension package and all of its language variants.
///
/// Keiyoushi ships extensions such as "Akuma" as a single APK containing dozens of language
/// sources (all, en, es, fr, ...). Flattened into individual rows that produced dozens of
/// identically named entries, so the store collapses them into one group per package.
public struct ExtensionCatalogGroup: Identifiable, Sendable {
    /// Stable identity for SwiftUI diffing.
    public var id: String { packageKey }
    public let packageKey: String
    public let name: String
    public let iconUrl: String?
    public let isNsfw: Bool
    /// Language variants ordered with `en` first, then `all`, then alphabetically.
    public let variants: [RemoteExtensionPackage]

    /// Preferred variant used when the user has not picked a language for this group.
    public var defaultVariant: RemoteExtensionPackage? { variants.first }

    public var defaultLanguage: String { variants.first?.lang ?? "en" }

    public var variantCount: Int { variants.count }
}

/// Groups a flat repository catalog into per-package rows.
public enum ExtensionCatalog {

    /// Groups packages by their parent `packageName` (falling back to the display name) and
    /// returns the groups sorted alphabetically.
    public static func group(_ packages: [RemoteExtensionPackage]) -> [ExtensionCatalogGroup] {
        var buckets: [String: [RemoteExtensionPackage]] = [:]
        var displayKeys: [String: String] = [:]

        for pkg in packages {
            let key = normalizedKey(for: pkg)
            buckets[key, default: []].append(pkg)
            if displayKeys[key] == nil {
                displayKeys[key] = pkg.name
            }
        }

        return buckets.compactMap { key, variants -> ExtensionCatalogGroup? in
            let sortedVariants = sortVariants(variants)
            guard let first = sortedVariants.first else { return nil }
            return ExtensionCatalogGroup(
                packageKey: key,
                name: displayKeys[key] ?? first.name,
                iconUrl: sortedVariants.compactMap { $0.iconUrl }.first,
                isNsfw: sortedVariants.contains { $0.isNsfw },
                variants: sortedVariants
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Language order: English first (most common default), then the language-neutral "all"
    /// source, then everything else alphabetically.
    public static func sortVariants(_ variants: [RemoteExtensionPackage]) -> [RemoteExtensionPackage] {
        variants.sorted { a, b in
            let rankA = languageRank(a.lang)
            let rankB = languageRank(b.lang)
            if rankA != rankB { return rankA < rankB }
            return a.lang.localizedCaseInsensitiveCompare(b.lang) == .orderedAscending
        }
    }

    public static func normalizedKey(for pkg: RemoteExtensionPackage) -> String {
        guard let packageName = pkg.packageName,
              !packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return pkg.name.lowercased()
        }

        // Keiyoushi package identifiers include the language segment, for example
        // `eu.kanade.tachiyomi.extension.en.mangakakalot`. Drop that one segment so the English,
        // Spanish, and language-neutral APKs are offered as one row with a language picker.
        let parts = packageName.split(separator: ".").map(String.init)
        if let extensionIndex = parts.lastIndex(of: "extension"),
           extensionIndex + 2 < parts.count {
            let prefix = parts[0...extensionIndex].joined(separator: ".")
            let slug = parts[(extensionIndex + 2)...].joined(separator: ".")
            return "\(prefix).\(slug)".lowercased()
        }

        return packageName.lowercased()
    }

    private static func languageRank(_ lang: String) -> Int {
        switch lang.lowercased() {
        case "en": return 0
        case "all": return 1
        default: return 2
        }
    }
}
