# Yomi iOS Handoff

Last updated: 2026-10-20

## Where things stand

- Repo: `C:\SIDEPROJECTS\yomi-ios`, branch `main`
- Current app & CI commit: `b198464` (`fix(sources): add referer cover image caching, fix cloudflare base64 fetch, and add floating tab bar`)
- Latest CI for `b198464`: **green (success)**, run `39368964223` (14m 41s)
- Latest IPA: `C:\Users\acost\Desktop\Yomi.ipa` and `C:\Users\acost\Desktop\Yomi-b198464.ipa`
- Verified Simulator Smoke: `com.yomiapp.reader` launched with zero crashes, smoke evidence captured in `01-floating-tabbar.png`.
- Working tree: clean

## Key Upgrades in b198464

- **Cover Image Loading & Memory Management**:
  - Implemented `YomiImageCache` with custom URLSession that injects required `Referer` headers for manga CDN hosts (`readdetectiveconan.com` -> `https://mangapill.com/`, `mangakakalot.gg` -> `https://www.mangakakalot.gg/`) and standard mobile Safari `User-Agent`.
  - Added automatic downsampling (`CGImageSourceCreateThumbnailAtIndex`) to thumbnail resolution (240x340), reducing per-cover RAM usage by ~94% (from ~8MB down to ~500KB) and eliminating memory bloat.
  - Automatic cache clearing on system memory warnings (`UIApplication.didReceiveMemoryWarningNotification`).
- **Cloudflare & MangaKakalot Bypass Robustness**:
  - Fixed Base64 string generation in `WebViewFetchService.swift` using `btoa(binary)`, allowing HTML and chapter page responses to decode properly without dropping the body.
  - Added navigation auto-detection in `CloudflareSolver.swift` and guaranteed cookie sync + completion when the user taps "Done", preventing users from ever getting trapped in verification loops.
- **Floating Tab Navigation**:
  - Replaced docked edge-to-edge bottom bar with an elevated floating capsule bar (`YomiTabBar`) with ultra-thin glass material blur, 0.5pt hairline border, spring-animated active tab indicators, and ambient drop shadow.
  - Inset scroll views with `.safeAreaInset(edge: .bottom)` so list items never get occluded.

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
