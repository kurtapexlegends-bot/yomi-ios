import Foundation
import Observation
import YomiCore

/// Central registry managing all active built-in and JavaScript community sources.
@Observable
public final class ExtensionManager: @unchecked Sendable {
    public static let shared = ExtensionManager()

    public private(set) var installedSources: [any SourceProtocol] = []

    private init() {
        reloadInstalledSources()
    }

    /// Reloads all installed sources from disk and registers the built-in MangaDex source.
    public func reloadInstalledSources() {
        var sources: [any SourceProtocol] = []

        // Register default native connectors: MangaPill (mainstream catalog) and MangaDex
        let mangaPill = MangaPillSource()
        sources.append(mangaPill)

        let mangaDex = MangaDexSource()
        sources.append(mangaDex)

        // Read dynamic JavaScript extensions from Application Support
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let extDir = appSupport.appendingPathComponent("Yomi/extensions", isDirectory: true)

            if fileManager.fileExists(atPath: extDir.path) {
                let fileURLs = try fileManager.contentsOfDirectory(at: extDir, includingPropertiesForKeys: nil)
                let jsFiles = fileURLs.filter { $0.pathExtension == "js" }

                for jsURL in jsFiles {
                    let sourceIdString = jsURL.deletingPathExtension().lastPathComponent
                    let metaURL = extDir.appendingPathComponent("\(sourceIdString).json")

                    guard fileManager.fileExists(atPath: metaURL.path),
                          let metaData = try? Data(contentsOf: metaURL),
                          let manifest = try? JSONDecoder().decode(SourceManifest.self, from: metaData),
                          var scriptContent = try? String(contentsOf: jsURL, encoding: .utf8) else {
                        continue
                    }

                    // Self-heal MangaKakalot scrapers to include modern DOM selectors (.itemupdate)
                    let isMangaKakalot = manifest.baseUrl.lowercased().contains("mangakakalot") || manifest.name.lowercased().contains("mangakakalot")
                    if isMangaKakalot {
                        let pkg = RemoteExtensionPackage(
                            id: manifest.id,
                            name: manifest.name,
                            lang: manifest.lang,
                            baseUrl: manifest.baseUrl,
                            iconUrl: manifest.iconUrl,
                            version: manifest.version,
                            scriptUrl: ""
                        )
                        let freshScript = ScraperScriptGenerator.generateScraperScript(for: pkg)
                        if freshScript != scriptContent {
                            try? freshScript.write(to: jsURL, atomically: true, encoding: .utf8)
                            scriptContent = freshScript
                        }
                    }

                    let jsExtension = JSExtension(manifest: manifest, scriptContent: scriptContent)
                    sources.append(jsExtension)
                }
            }
        } catch {
            print("[ExtensionManager] Failed to read local extensions directory: \(error)")
        }

        self.installedSources = sources
    }

    /// Finds a source by its unique 64-bit integer ID.
    public func getSource(id: Int64) -> (any SourceProtocol)? {
        installedSources.first { $0.manifest.id == id }
    }

    /// Uninstalls and removes a third-party extension from disk.
    public func uninstallExtension(sourceId: Int64) throws {
        guard sourceId != MangaDexSource.sourceId && sourceId != MangaPillSource.sourceId else {
            throw YomiError.storageError("Built-in native connectors cannot be uninstalled.")
        }

        let fileManager = FileManager.default
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let extDir = appSupport.appendingPathComponent("Yomi/extensions", isDirectory: true)

        let scriptURL = extDir.appendingPathComponent("\(sourceId).js")
        let metaURL = extDir.appendingPathComponent("\(sourceId).json")

        if fileManager.fileExists(atPath: scriptURL.path) {
            try fileManager.removeItem(at: scriptURL)
        }
        if fileManager.fileExists(atPath: metaURL.path) {
            try fileManager.removeItem(at: metaURL)
        }

        reloadInstalledSources()
    }
}
