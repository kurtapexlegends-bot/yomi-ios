# Yomi (読み) — Manga Reader for iOS & iPadOS

> **A modern, high-performance, open-source manga reader engineered natively for iOS and iPadOS.**  
> Built with Swift 5.10 / Swift 6, SwiftUI, hybrid UIKit viewport with CATiledLayer, JavaScriptCore community extension runtime, and GRDB SQLite.

---

## Highlights & Features

### 🚀 High-Performance Reader Engine
- **Hybrid Viewport:** Custom `UICollectionView` backed by `CATiledLayer` for stutter-free 120Hz ProMotion continuous webtoon scrolling.
- **Memory Sub-Sampling:** Employs `CGImageSourceCreateThumbnailAtIndex` to eliminate out-of-memory crashes on 4K webtoons.
- **Reading Modes:** Webtoon (continuous vertical), Right-to-Left (traditional Japanese manga), Left-to-Right, Continuous Horizontal, and Dual-Page Spread.
- **Autocrop Borders:** Automatic detection and cropping of whitespace and scan letterboxes.
- **Post-Processing:** Independent brightness slider, OLED True Black color inversion, and contrast enhancement.
- **5 Tap Navigation Layouts:** Customizable touch zones and hardware volume button paging.

### 🧩 Extension Ecosystem & Scraper Runtime
- **JavaScriptCore VM:** Sandboxed `.js` community scrapers executed in an isolated runtime without Node.js overhead.
- **Native Swift Bridges:** Blazing-fast HTML DOM parsing powered by `SwiftSoup`, native `fetch` over `URLSession`, and cryptographic helpers.
- **Built-in MangaDex Connector:** Ships with a production-grade native connector for the official MangaDex API (v5) for out-of-the-box reading.
- **Anti-Bot & Cloudflare Solver:** Automated headless `WKWebView` cookie resolution with a fallback in-app interactive captcha sheet for manual Cloudflare Turnstile challenges.
- **Community Repositories:** Add third-party extension repositories with one-tap installation and updates.

### 🔄 Tachiyomi / Mihon Parity & Sync
- **Tachiyomi Backup Import & Export:** Full compatibility with `.tachibk` archives (restore your entire Android library, categories, and tracking on iOS).
- **Apple iCloud Sync:** Seamless real-time reading progress synchronization between iPhone and iPad via `NSUbiquitousKeyValueStore`.
- **External Manga Trackers:** Built-in AniList and MyAnimeList OAuth2 tracking with automatic progress updates upon chapter completion.
- **Source Migration Tool:** Batch migrate manga across sources when an aggregator changes domains, preserving read status and bookmarks.

### 📥 Background Downloads & Offline Storage
- **Out-of-Process Background Daemon:** Downloads continue seamlessly via `URLSessionConfiguration.background` even when the app is suspended.
- **CBZ Comic Archiver:** Saves chapters as portable `.cbz` zip archives with standard `ComicInfo.xml` metadata.
- **ActivityKit Dynamic Island:** Live Activities tracking download progress in real time on Lock Screen and Dynamic Island.
- **Local Comic Importer:** Drag-and-drop or AirDrop local `.cbz`, `.cbr`, and `.zip` files from the iOS Files app into your library.

### 🔒 Privacy & Biometric Security
- **Face ID & Touch ID App Lock:** Biometric app protection with configurable grace periods (Immediately, 1m, 5m, 15m, 30m).
- **Incognito Mode:** One-tap toggle disabling reading history logging, tracker mutations, and cookie storage.
- **Multitasking Snapshot Privacy:** Automatic blur shield whenever the app enters the iOS App Switcher.
- **Category Locks:** Lock specific sensitive library categories behind biometric authentication.

### 📱 Modern iOS & iPadOS HIG
- **iPadOS NavigationSplitView:** Multi-column sidebar layout, keyboard shortcuts, and Apple Pencil support.
- **OLED True Black:** High-contrast pure black aesthetic designed for iPhone OLED screens.

---

## Architecture Overview

Yomi is organized as a modular Swift Package Manager workspace:

```
Sources/
├── YomiCore/         # Domain models (Manga, Chapter, Category, Source, Track), Biometrics, Privacy
├── YomiDatabase/     # GRDB.swift SQLite WAL database, migrations, FTS5 instant search, repositories
├── YomiExtensions/   # JavaScriptCore engine, SwiftSoup DOM bridge, Cloudflare solver, MangaDex client
├── YomiReader/       # Hybrid UIKit UICollectionView + CATiledLayer, Autocrop, ZoomablePageScrollView
├── YomiDownload/     # Background URLSession daemon, CBZ archiver, ActivityKit Live Activities
├── YomiSync/         # Tachiyomi .tachibk backup parser/serializer, iCloud sync, AniList/MAL clients
├── YomiUI/           # Modern SwiftUI views (Library, MangaDetail, Browse, Downloads, Settings)
└── YomiApp/          # @main entry point, BackgroundTasks registration, AirDrop file handlers
```

---

## Sideloading & Installation

Yomi is designed to be dual-ready:
1. **Sideloading (Recommended for full functionality):**
   - **AltStore / SideStore:** Download the latest unsigned `Yomi.ipa` from Releases and install via AltStore.
   - **TrollStore (iOS 15.0 - 17.0):** Direct permanent installation with zero periodic re-signing.
   - **Sideloadly:** Sideload with a free or paid Apple Developer account.
2. **Building from Source:**
   - Clone the repository: `git clone https://github.com/yomiapp/yomi-ios.git`
   - Open the directory in Xcode 15 or 16 on macOS.
   - Select your iOS device or simulator and hit **Run** (`CMD+R`).

---

## Extension Development

Refer to [EXTENSIONS_SPEC.md](EXTENSIONS_SPEC.md) for the complete JavaScript API reference and sample scrapers.

---

## License

Licensed under the MIT License.
