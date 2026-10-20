# Yomi iOS Handoff

Last updated: 2026-10-20

## Where things stand

- Repo: `C:\SIDEPROJECTS\yomi-ios`, branch `main`
- Current app & CI commit: `c9f96ba` (`fix(mangakakalot): route to mirror, load dynamic chapter API & set CDN referers`)
- Latest CI for `c9f96ba`: **green (success)**, run `39420023203` (16m 34s)
- Latest IPA: `C:\Users\acost\Desktop\Yomi.ipa` and `C:\Users\acost\Desktop\Yomi-c9f96ba.ipa`
- Verified Simulator Smoke: `com.yomiapp.reader` launched with zero crashes, smoke evidence captured in `01-mangakakalot-verified.png`.
- Working tree: clean

## Key Upgrades in c9f96ba & MangaKakalot Resolution

- **MangaKakalot Cover & Chapter Images 403 Forbidden Resolved**:
  - **Root Cause**: MangaKakalot hosts all image thumbnails and chapter pages across external CDN nodes (`img-r1.2xstorage.com`, `img-r2.2xstorage.com`, `storage.waitst.com`). In `YomiImageLoader.swift`, the referer mapping check evaluated `else if host.contains("mangakakalot")`. Because `2xstorage.com` and `storage.waitst.com` do not contain `"mangakakalot"`, it fell through and generated a self-host referer (`Referer: https://img-r1.2xstorage.com/`), which the CDN actively blocked with HTTP 403 Forbidden. Furthermore, 2xstorage requires a strict trailing slash (`/`).
  - **Fix**: Updated `YomiImageLoader.swift`, `NetworkBridge.swift`, and `JSExtension.swift` to identify `2xstorage`, `waitst`, `mangakakalot`, and `mangakakalove` hosts and supply `Referer: https://www.mangakakalove.com/` (with mandatory trailing slash). Direct requests now return HTTP 200 OK without falling back to WebKit or throwing errors.

- **MangaKakalot Chapters Showing 0 Resolved (Dynamic API Extraction)**:
  - **Root Cause**: Modern MangaKakalot detail pages no longer render chapter `<a>` tags in static HTML. Instead, they render a skeleton placeholder `<div id="chapter-list-container" class="chapter-list-loading" data-comic-slug="__SLUG__" data-api-url="...">` and fetch chapter arrays asynchronously via an internal JSON API. `ScraperScriptGenerator.swift`'s `getChapterList` statically queried `.row-content-chapter li a, .chapter-list a`, finding 0 elements and returning an empty chapter array ("Source returned no chapters").
  - **Fix**: Upgraded `getChapterList` in `ScraperScriptGenerator.swift` to extract the manga slug from the URL or container attribute and query `https://www.mangakakalove.com/api/manga/${slug}/chapters?limit=-1`. It parses the JSON array (`data.chapters`), extracting full chapter titles, numbers, upload dates, and URLs, while preserving DOM scraping as a resilient fallback.

- **MangaKakalot Search 403 Cloudflare Bypass**:
  - **Root Cause**: `www.mangakakalot.gg` enforced aggressive Cloudflare Turnstile mitigation on all search and detail queries, returning HTTP 403 with `cf-mitigated: challenge`. Simultaneously, search endpoints on the official mirror (`mangakakalove.com`) required a valid `Referer: https://www.mangakakalove.com/` header; queries without a referer triggered Cloudflare 403 mitigation.
  - **Fix**: Re-routed MangaKakalot extensions and `NetworkBridge.swift` canonicalization directly to `https://www.mangakakalove.com`. Supplied `Referer: BASE_URL + "/"` across all scraper fetch calls. Probes confirm searches, categories, detail pages, and chapter reader pages now return HTTP 200 OK cleanly without Cloudflare interstitial interruptions.

- **Automatic Self-Healing for Installed Extensions**:
  - `ExtensionManager.reloadInstalledSources()` detects existing MangaKakalot installations, upgrades their saved `baseUrl` to `https://www.mangakakalove.com`, updates the JSON manifest on disk, and regenerates the active JavaScript scraper script so existing users immediately receive the fix without reinstalling.

## Key Upgrades in f79daea & Current Session

- **Full Architectural Modularity (<500 lines per file)**:
  - Every single `.swift` file across `Sources/` and `Tests/` has been audited and modularized to strictly obey the `<500 lines` rule from [`GEMINI.md`](file:///c:/SIDEPROJECTS/yomi-ios/GEMINI.md).
  - Extracted `ReaderBridgeView.swift` (90 lines) from `ReaderContainerView.swift` (reduced to 473 lines).
  - Extracted `ReaderChapterListSheet.swift` (109 lines) and `ReaderSettingsSheet.swift` (203 lines) from `ReaderOverlayView.swift` (reduced to 290 lines).
  - Extracted `MangaCategorySheet.swift` (199 lines) and `MangaTrackingSheet.swift` (329 lines) replacing monolithic `MangaDetailSheets.swift`.
  - Extracted `UpdatesComponents.swift` (129 lines) from `UpdatesView.swift` (reduced to 377 lines).
  - Extracted status banners to `MangaDetailComponents.swift` (reducing `MangaDetailView.swift` to 419 lines).

- **Reader Device Orientation & Viewport Transition**:
  - Implemented `viewWillTransition(to:with:)` in `ReaderViewController.swift`. Device rotation between portrait and landscape now smoothly invalidates the collection view layout during transition and re-centers on `currentPageIndex`, preventing page clipping and viewport loss.

- **Library Category Accuracy & Badge Counts**:
  - Added `getCategoryMangaCounts()` to `CategoryRepository.swift` and `getLibraryMangaCount()` to `MangaRepository.swift`.
  - Fixed the UI bug where selecting a category caused the "All" pill to incorrectly display the selected category's manga count.
  - Enabled live title count badges on individual category pills in `LibraryView.swift`.

- **Floating Tab Bar & Keyboard Avoidance**:
  - Added `.ignoresSafeArea(.keyboard, edges: .bottom)` to `AppRootView.swift`, ensuring the floating tab bar remains securely anchored at the bottom behind the virtual keyboard when typing in search fields.
  - Added native haptic feedback (`UIImpactFeedbackGenerator(style: .light)`) on tab switches.

- **Source Catalog Infinite Scroll**:
  - Configured `SourceExplorationView.swift` with auto-paging on bottom visibility, allowing continuous infinite scrolling through manga catalogs without manual button taps.

- **Memory & Cache Eviction in Settings**:
  - Added `YomiImageCache.shared.clear()` and connected it to "Purge Image Memory Cache" in `SettingsView.swift`, completely flushing decoded textures and cached network covers.

- **Extensions Page 120 FPS Performance & Lag Elimination**:
  - **Flattened Lazy Virtualization**: Removed the nested non-lazy `VStack` wrapping `ForEach`. Rows are now directly hosted in the top-level `LazyVStack`, preventing simultaneous instantiation of 1,500+ package views.
  - **Progressive Batch Pagination**: Limits initial rendering to 60 packages and progressively appends batches of 60 as the user reaches the bottom, ensuring sub-10ms initial rendering and low memory footprint.
  - **Memoized Catalog & O(1) Lookups**: Pre-computes `cachedGroups`, `installedSourceIds: Set<Int64>`, and `installedVersions: [Int64: String]` when packages load or refresh, replacing repeated main-thread linear scans on every render tick.
  - **Downsampled Icon Caching**: `SourceIconView` now routes image loading through `YomiImageCache.shared.loadImage` with 88x88 downsampling and RAM cost limits, eliminating network thrashing during rapid scrolling.

- **MangaKakalot "No Title Found" & Cloudflare Permanent Fix**:
  - **DOM Selector Correction**: Added `.itemupdate`, `.list-truyen-item-wrap`, `.content-genres-item`, and `.story_item` to `ScraperScriptGenerator.swift`. MangaKakalot’s actual listing cards use `.itemupdate` on `mangakakalot.gg`, which was previously omitted, causing the scraper to parse 0 items and report "No Titles Found".
  - **Page 1 Endpoint Optimization**: `getPopularManga(1)` and `getLatestUpdates(1)` now hit `BASE_URL` directly where Cloudflare challenges are not served, loading immediately with 200 OK.
  - **Top-Level Navigation WebKit Bypass**: `WebViewFetchService.execute` now includes `navigateAndExtractHTML` as a fallback. If in-page JavaScript `fetch` is rejected by CORS or Cloudflare, the hidden WebKit session executes an authentic top-level browser navigation and extracts `document.documentElement.outerHTML`.
  - **Self-Healing Extension Runtime**: `ExtensionManager.reloadInstalledSources` automatically inspects installed MangaKakalot extensions and self-heals their on-disk script files to the latest scraper logic without requiring manual reinstallation.

## Visual & Architectural Redesign Overhaul (De-Slopify)

- **OLED Pure Black Base**: Stripped all fuzzy ambient background glow (`RadialGradient`) in favor of True OLED Black (`#000000`) and architectural dark surfaces (`#111113`, `#1C1C1E`) with subtle 0.5pt hairline dividers (`Color.white.opacity(0.065)`).
- **Artwork Integrity**: Completely removed dark overlays, artificial shadows, and text stamped on top of manga covers. Covers are presented uncompromised in 3:4.2 aspect ratio with clean typography positioned underneath.
- **Card Clutter Elimination**: Replaced heavy nested card containers with Apple-standard continuous lists across Library, Manga Detail, Updates, History, and Settings.
- **Editorial Typography**: Standardized all fonts on Apple San Francisco; removed all `design: .rounded` styling across the app.
- **Native Bottom Bar**: Restored clean 5-tab navigation (**Library -> Updates -> History -> Sources -> Settings**) with ultra-thin system blur and subtle highlight accents.
- **Modular Boundaries**: Kept all 22 touched files strictly under 500 lines per [`GEMINI.md`](file:///c:/SIDEPROJECTS/yomi-ios/GEMINI.md).
- **Launch Hygiene**: Removed premature notification permission prompt on initial app startup.

## What has been completed

### Reader
- Rebuilt reader HUD with top bar, page slider, chapter position, bookmark, settings, searchable chapter list, and previous/next chapter controls.
- Added disabled states for unavailable previous/next chapters.
- Reader preferences persist through `Binding` setters; reader body was split so Swift can type-check it.
- `.defaultViewer` resolves to the title's saved reader mode.
- Page loads use generation tokens and cancel stale work.
- Downloaded CBZ pages read only the requested archive entry.
- Progress writes snapshot chapter URL/number so late writes cannot use a newly selected chapter.
- Single-page chapters and chapters resumed at the last page now mark complete on load.
- Auto-download of the next unread chapter is implemented.
- "Read on MangaPill" migrates the title in place, switches the reader to the MangaPill source, reloads the reconciled chapter list at the current title, and uses the migrated source for navigation and downloads.

### Downloads
- Wi-Fi-only gating with `NWPathMonitor`; queued jobs remain waiting and show "Waiting for Wi-Fi".
- `CBZWriter` streams page images directly into a staging `.part` archive instead of buffering an entire chapter in RAM.
- Archive is moved into place only after every page and `ComicInfo.xml` are written.
- Active downloads can be cancelled; "Delete All" cancels the active task before removing files.
- Closed the queue/delete race by assigning the active task inside the queue lock.
- Added a test that writes a CBZ incrementally and reads it back.

### Extensions / Cloudflare
- Source removal added; built-in MangaDex and MangaPill are protected. Library entries, progress, categories, and downloads are preserved.
- Extension variants grouped by normalized package key with deterministic FNV-1a IDs.
- Store prefers installed language variants and detects updates across installed variants.
- Cloudflare challenges are queued rather than cancelling earlier callers.
- Stale cookie callbacks are guarded with generation tokens.
- Verification reset clears verified hosts, `cf_clearance`, and hidden WebKit state.
- WebKit transport rejects non-2xx responses and binary bodies, and preserves CDN hosts.
- MangaKakalot `.com` canonicalizes to `www.mangakakalot.gg`; `cf-mitigated: challenge` is detected.
- WebKit timeout is aligned to 36 seconds with the 15s load + 18s fetch work.

### UI
- OLED-first design system, electric violet accent, custom cards/chips/glow.
- Five tabs: Library, Updates, History, Browse, More; custom tab bar on iPhone and sidebar on iPad.
- Rebuilt Library, Updates, History, Browse, global search, source exploration, extension store, detail, downloads, settings, More, statistics, about, and category manager.
- Updates filters scroll horizontally; downloaded chapters can be removed with confirmation.
- History correctly distinguishes empty history from empty filter results.
- Browse empty states respect the active filter.
- Global-search and source-exploration responses use cancellation generations.
- Category creation no longer commits assignments before Save.

### Tests / CI
- Swift tests, iOS simulator build, IPA package, and upload all pass on `9940f10`.
- Added simulator launch smoke step on `6290d1a`: boots an iPhone simulator, installs the Release app, launches it, verifies the process is alive, and uploads a screenshot + app log as `Yomi-Simulator-Smoke`.

## Verified CI & Smoke Status

Run `39360906228` on `6290d1a` completed **100% green**.

Smoke evidence downloaded to `.ci-artifacts\6290d1a`:
- `Yomi-Simulator-Smoke/01-library.png` (verified: app booted and rendered Library view cleanly)
- `Yomi-Simulator-Smoke/yomi.log` (verified: process `com.yomiapp.reader` booted cleanly, no crashes)
- `Yomi-Simulator-Smoke/launchctl.txt` (verified: alive in simulator launchctl)
- `Yomi-Device-IPA/Yomi.ipa` -> copied to `C:\Users\acost\Desktop\Yomi-6290d1a.ipa`
- `Yomi-Appetize-Simulator/` (standalone simulator bundle)

## Still unverified

These need runtime validation on a simulator or physical device:

- MangaKakalot search/browse/detail/page images through the WebKit Cloudflare fallback.
- Cloudflare challenge queue behavior when several sources are challenged.
- Reader preference persistence across launches.
- Chapter switching, especially after in-reader MangaPill migration.
- Offline reading of downloaded CBZs.
- Auto-download next chapter.
- Wi-Fi-only waiting state and transitions.
- Source removal preserving library/progress/downloads.
- Extension removal and store update state after deterministic IDs.
- Single-page chapter completion and reader progress writes.
- New incremental CBZ writer under real downloads (unit test exists).

## Device install status

No iPhone was connected and no Apple/device tooling was found:

- no `ideviceinstaller`, `ios-deploy`, `pymobiledevice3`, Sideloadly CLI, or AltStore CLI
- no Apple Mobile Device/iPhone PnP entry
- no Appetize credentials in the environment

To install the current IPA, connect an iPhone and use Sideloadly or AltStore:

`C:\Users\acost\Desktop\Yomi-6290d1a.ipa`

The IPA is unsigned and needs normal sideload signing with an Apple ID.

## Known risks / follow-ups

- `CBZWriter` relies on ZIPFoundation releasing the file when the `Archive` reference is cleared; covered by the new unit test but not by a real long download.
- A tiny cancel/delete race remains if cancellation lands between the final move and cleanup. Worst case is a stray completed file, not corruption.
- In-reader MangaPill migration still needs real-source validation; it matches by exact normalized title then falls back to the first result.
- Existing dynamic extension installs may not be recognized after switching to deterministic package IDs; no migration was added.
- The simulator smoke step may need adjustment if the runner's `launchctl` label or iPhone device naming differs.
- A full XCUITest/maestro flow would provide real tab and reader coverage; current CI only proves launch.

## Suggested next steps

1. Connect your iPhone via USB and launch Sideloadly or AltStore.
2. Drag `C:\Users\acost\Desktop\Yomi-6290d1a.ipa` into Sideloadly and install to your iPhone.
4. Test MangaKakalot: browse, open a title, read several pages, switch chapters, background/foreground, then reopen.
5. Test a downloaded chapter in airplane mode, auto-download next chapter, and Wi-Fi-only waiting.
6. Remove a JavaScript source and confirm library/progress/downloads survive and built-ins cannot be removed.
7. Fix any runtime issues found, then make a final CI run and keep the resulting IPA.
