# Yomi (`com.yomiapp.reader`) — Agent Directives & Architecture Guide

> **Core Philosophy:** High-performance, zero-OOM, native Swift comic and manga reader for iOS 17+ and iPadOS 17+. Disciplined pair-programming, clean modular architecture, strict memory ceilings, zero fluff, and zero UI slop.

---

## 1. Project Overview & Target Architecture
- **Language & Runtime:** Native Swift 5.10 / Swift 6 compatibility targeting **iOS 17.0+** and **iPadOS 17.0+**.
- **Package Manager:** Swift Package Manager (SPM) with 8 modular targets + XcodeGen (`project.yml`) for iOS Simulator `.app` and device `.ipa` packaging.
- **Repository Location:** [kurtapexlegends-bot/yomi-ios](https://github.com/kurtapexlegends-bot/yomi-ios) (`c:\SIDEPROJECTS\yomi-ios`).

### Modular Architecture Map
1. [`Sources/YomiCore`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore): Universal domain models ([`Manga`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Models/Manga.swift), [`Chapter`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Models/Chapter.swift), [`YomiCategory`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Models/Category.swift), [`Track`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Models/Track.swift)), [`BiometricSecurityManager`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Security/BiometricSecurityManager.swift), [`PrivacyManager`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Security/PrivacyManager.swift). Zero dependencies.
2. [`Sources/YomiDatabase`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiDatabase): `GRDB.swift` SQLite engine in WAL mode with foreign keys, FTS5 full-text indexing, and CRUD repositories.
3. [`Sources/YomiExtensions`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiExtensions): Sandboxed `JavaScriptCore` runtime, native bridges (`fetch` over `URLSession`, `HTMLBridge` via `SwiftSoup`, `CryptoBridge`), [`CloudflareSolver`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiExtensions/Engine/CloudflareSolver.swift), community repo parser ([`RepoManager`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiExtensions/Engine/RepoManager.swift)), and native [`MangaDexSource`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiExtensions/Sources/MangaDexSource.swift).
4. [`Sources/YomiReader`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiReader): Hybrid UIKit `UICollectionView` backed by `CATiledLayer`, ImageIO downsampler, whitespace autocrop, 5 customizable tap zones, OLED True Black color inversion.
5. [`Sources/YomiDownload`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiDownload): Background `URLSession` queue daemon, `.cbz` archiver with `ComicInfo.xml`, `ActivityKit` Live Activities for Lock Screen / Dynamic Island, local comic importer.
6. [`Sources/YomiSync`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiSync): Tachiyomi/Mihon `.tachibk` Protobuf backup serializer/deserializer, iCloud sync coordinator, AniList OAuth2 tracking client, smart source migration tool.
7. [`Sources/YomiUI`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI): SwiftUI views: [`LibraryView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Library/LibraryView.swift), [`MangaDetailView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Manga/MangaDetailView.swift), [`BrowseView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Browse/BrowseView.swift), [`ExtensionStoreView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Browse/ExtensionStoreView.swift), [`DownloadsView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Downloads/DownloadsView.swift), [`SettingsView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Settings/SettingsView.swift), [`ReaderContainerView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Reader/ReaderContainerView.swift), [`AppRootView`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiUI/Navigation/AppRootView.swift).
8. [`Sources/YomiApp`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiApp): `@main YomiApp` entrypoint, [`AppDelegate`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiApp/AppDelegate.swift), [`LibraryUpdateScheduler`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiApp/Background/LibraryUpdateScheduler.swift) (`BGTaskScheduler`).

---

## 2. Architectural Boundaries & Performance Invariants

### 1. Structural Size Boundaries
- **File Size Cap:** Strictly <500 lines per file. Any file approaching this threshold must be decomposed into granular domain components.
- **View Controllers & Coordinators:** Maximum 250 lines per class/controller. Delegate rendering, data transforms, and lifecycle logic to dedicated services.
- **Entrypoints & Handlers:** Maximum 50 lines per method. Use early guard returns to prevent nesting deeper than 2 levels.

### 2. Zero-OOM Reader & Memory Ceilings
- **Sub-Sampling Before Allocation:** Never decode full-resolution images into raw `UIImage` memory without downsampling. Always route remote and local image data through [`ImageDownsampler.shared.downsample(data:to:scale:)`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiReader/Processing/ImageDownsampler.swift) via `CGImageSourceCreateThumbnailAtIndex`.
- **Memory Cache Budget:** The image memory cache (`NSCache`) is strictly hard-capped at **150MB** and 60 objects. In-flight reader cells must flush when dequeued.
- **CATiledLayer Continuous Scrolling:** Continuous vertical (Webtoon) reader cells must utilize `CATiledLayer` tiling to render 4K long-strip pages incrementally without GPU texture memory spikes.

### 3. Swift Concurrency & Strict Types
- **Sendable Compliance:** All domain models, records, and repositories must conform to `Sendable`.
- **No Unsafe Concurrency Hacks:** Never apply `@unchecked Sendable` unless isolating OS-level thread-safe primitives (such as `NSCache` or `os_unfair_lock`).
- **MainActor Boundary:** All UI view models, navigation coordinators, and SwiftUI views must execute on `@MainActor`.
- **Objective-C Runtime Safety:** Never introduce bare `Category` types in `YomiCore` or `YomiDatabase`. Always name domain categories [`YomiCategory`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiCore/Models/Category.swift) to prevent naming collisions with Apple's `ObjectiveC.Category` runtime typealias.

### 4. Database Integrity (GRDB & SQLite)
- **WAL Mode Mandatory:** SQLite must run in Write-Ahead Logging (`WAL`) mode with foreign key constraints enabled.
- **Additive Migrations Only:** Never execute destructive schema drops (`DROP TABLE`) or table wipes. Always implement versioned migrations (`v1`, `v2`, `v3`) in [`SchemaMigrations.swift`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiDatabase/Migrations/SchemaMigrations.swift).
- **Primary Key Lookups:** Always use GRDB's standard `fetchOne(db, key: id)` and `deleteOne(db, key: id)`.
- **FTS5 Synchronization:** The full-text search index table `mangas_fts` must remain synced with `mangas` via SQLite triggers (`after_insert`, `after_update`, `after_delete`).

---

## 3. App Store Compliance vs. Sideloading Architecture
- **Dual-Ready Compliance Separation:**
  - **The Core Binary:** Functions as a clean, compliant local reader. It supports on-device comic imports (`.cbz`, `.cbr`, `.zip`) with `ComicInfo.xml` metadata, local reading history, categories, and tracking.
  - **Zero Bundled Scrapers:** Never hardcode infringing third-party scrapers or piracy URLs directly into the core binary.
  - **Dynamic Extensions Sandbox:** Third-party scrapers run dynamically inside isolated `JavaScriptCore` virtual machines loaded from user-added repository URLs (`index.json`). If extensions are absent, the application remains fully functional as an offline comic library.

---

## 4. UI/UX Design Standards ("Zero AI Slop")
- **True Black OLED Palette:**
  - Background: `YomiTheme.pureBlack` (`#000000`).
  - Cards & Bars: `YomiTheme.surface` (`secondarySystemBackground`) and `.ultraThinMaterial`.
  - Accent: `YomiTheme.accent` (`Color.indigo`).
- **Strictly Banned UI Patterns:**
  - **No Decorative Emojis:** Ban inline emojis in buttons, tab bars, headers, and alerts. Use Apple SF Symbols exclusively (e.g., `Image(systemName: "books.vertical.fill")`).
  - **No Gradient Slop:** Ban multi-color gradient borders, rainbow button strokes, and cheesy gradient cards. Adhere strictly to Apple Human Interface Guidelines (HIG).
  - **No Lazy Placeholders:** Never commit `// implement later`, `/* TODO */`, or dummy stubs. Every view must be complete and syntactically valid.

---

## 5. Cross-Platform SPM & CI/CD Discipline

### 1. Cross-Platform SPM Hygiene
- GitHub Actions runs unit tests on `macos-14` Apple Silicon runners. When `swift test` builds the package targets on macOS, iOS-only frameworks (`UIKit`, `ActivityKit`, `BackgroundTasks`, iOS-only modifiers) are not present.
- **Mandatory Guard Rules:**
  - Any UIKit import must be guarded with `#if canImport(UIKit) ... #else ... #endif` providing a non-failing stub for macOS.
  - Any `BGTaskScheduler` calls must be guarded with `#if os(iOS)`.
  - Use cross-platform SwiftUI toolbar placements (`.cancellationAction`, `.primaryAction`, `.confirmationAction`) rather than platform-locked `.topBarLeading` or `.topBarTrailing`.
  - Guard iOS-only view modifiers (`.listStyle(.insetGrouped)`, `.fullScreenCover`) with `#if os(iOS)`.

### 2. CI/CD Packaging Pipeline (XcodeGen)
- **Project Generator:** [`project.yml`](file:///c:/SIDEPROJECTS/yomi-ios/project.yml) generates `Yomi.xcodeproj` linking local package targets.
- **Workflow:** [`.github/workflows/build-and-test.yml`](file:///c:/SIDEPROJECTS/yomi-ios/.github/workflows/build-and-test.yml) executes:
  1. `swift test -v` (Unit test suite verification).
  2. `brew install xcodegen && xcodegen generate` (Xcode project generation targeting Xcode 16+).
  3. `xcodebuild build -scheme Yomi -destination "generic/platform=iOS Simulator"` -> Produces `Yomi-Simulator.zip` containing `Yomi.app/` for **Appetize.io**.
  4. `xcodebuild build -scheme Yomi -destination "generic/platform=iOS"` -> Produces `Yomi.ipa` inside `Payload/` for **Sideloadly / AltStore**.

---

## 6. Extension Runtime & Scraper Contract
- **Sandbox Boundary:** Scrapers execute in isolated `JSContext` virtual machines. They have zero access to the device filesystem, Keychain, network hardware, or user biometrics.
- **Standard Native Bridges:**
  - `fetch(url, options)`: Dispatches asynchronous HTTP/HTTPS requests through native `URLSession`.
  - `HTMLBridge.parse(html)`: Native DOM selector querying powered by `SwiftSoup` (supports `.select(css)`, `.text()`, `.attr(name)`).
  - `CryptoBridge`: Native MD5, SHA256, and Base64 routines.
- **Cloudflare & Turnstile Challenges:** Handled transparently by [`CloudflareSolver.shared`](file:///c:/SIDEPROJECTS/yomi-ios/Sources/YomiExtensions/Engine/CloudflareSolver.swift) using headless `WKWebView` with an on-demand interactive presentation sheet for user-solved captchas.
- **Complete Specification:** Refer to [`EXTENSIONS_SPEC.md`](file:///c:/SIDEPROJECTS/yomi-ios/EXTENSIONS_SPEC.md) for manifest formats, sample scraper code, and packaging guidelines.

---

## 7. Developer & Agent Operational Rules
- **Inspect State First:** Never speculate or make blind edits. Inspect source files and verify line numbers before making modifications.
- **No Unsolicited Dependencies:** Never add SPM packages or Cocoapods without explicit instruction.
- **No Destructive Git Commands:** Never execute `git reset --hard`, `git push --force`, or unprompted file wipes.
- **Automated CI Push Protocol:** The user has authorized automatically committing and pushing verified code changes to `origin main` upon task completion so that the GitHub Actions build and packaging pipeline (`Yomi-Device-IPA`) automatically triggers without manual prompts.
- **Deterministic CI Verification:** Before marking a milestone as complete, verify that the GitHub Actions CI pipeline passes green and build artifacts are generated.
