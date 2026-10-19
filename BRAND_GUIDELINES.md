# Yomi — Brand & Logo Guidelines (Master Specification)

> **Core Identity:** Yomi (*読み*, Japanese for "reading") is a high-performance, native iOS comic and manga reader engineered for pure OLED focus, instantaneous navigation, and architectural restraint.

---

## 1. The Master Mark

The Yomi mark (**"The Architectural Gutter 'Y'"**) synthesizes two foundational elements:
1. **The Letterform "Y"**: An asymmetric, high-velocity monogram recognizable from across a room.
2. **Manga Panel Gutters**: A floating diagonal facet separated from the main monolithic spine by a razor-sharp negative space gutter, echoing the rhythm of reading comic panels.

### Deliverable Variants
- `final-symbol.svg`: One-color pure black master vector on transparent canvas (`viewBox="0 0 256 256"`).
- `final-symbol-oled.svg`: Stark White master on `#000000` True Black OLED canvas.
- `final-symbol-accent.svg`: Electric Violet (`#7C5CFC`) floating panel + Stark White spine on `#000000`.
- `final-horizontal.svg`: Master lockup pairing the symbol with the custom vector geometric wordmark **YOMI** on a `720x256` canvas.
- `final-symbol-app-icon.svg`: Apple rounded-squircle tile for iOS home screen simulation.

---

## 2. Clear Space & Proportions

The clear space rule preserves the mark's visual authority. Always maintain a minimum exclusion zone of **$1\times X$** on all four sides:
- **$X$ (The Gutter Unit)** = The exact width of the diagonal negative-space channel ($10\,\text{px}$ on a $256\,\text{px}$ canvas, or $\approx 4\%$ of the mark's total footprint).
- No UI controls, text, or extraneous decorative elements may intrude into this boundary.

---

## 3. Scale Ladder & Minimum Sizes

| Format | Minimum Safe Size | Recommended File |
| :--- | :--- | :--- |
| **Favicon / Browser Tab** | $16\times 16\,\text{px}$ | `favicon-16.png` / `favicon.ico` |
| **iOS Status Bar / Compact Avatar** | $32\times 32\,\text{px}$ | `final-symbol-favicon-32.png` |
| **iOS Spotlight / Settings** | $60\times 60\,\text{px}$ | `AppIcon-60@2x.png` ($120\times 120\,\text{px}$) |
| **iPhone Home Screen** | $60\times 60\,\text{pt}$ ($3\times$) | `AppIcon-60@3x.png` ($180\times 180\,\text{px}$) |
| **iPad Pro Home Screen** | $83.5\times 83.5\,\text{pt}$ ($2\times$) | `AppIcon-83.5@2x.png` ($167\times 167\,\text{px}$) |
| **App Store Master** | $1024\times 1024\,\text{px}$ | `AppIcon-1024.png` |
| **Horizontal Lockup** | $120\,\text{px}$ wide | `render-horizontal.png` |

---

## 4. Color Palette

All colors are strictly calibrated for OLED panels, high dynamic range displays, and Apple Human Interface Guidelines:

| Swatch | Name | HEX | RGB | CMYK | Usage |
| :---: | :--- | :--- | :--- | :--- | :--- |
| ⬛ | **True Black (OLED)** | `#000000` | `0, 0, 0` | `75, 68, 67, 90` | Primary app canvas, icon background, letterbox borders |
| ⬜ | **Stark White** | `#FFFFFF` | `255, 255, 255` | `0, 0, 0, 0` | Primary mark spine, wordmark, primary typography |
| 🟪 | **Electric Violet** | `#7C5CFC` | `124, 92, 252` | `66, 71, 0, 0` | Floating panel accent, interactive tints, active tab pills |
| ◼️ | **Deep Surface** | `#161618` | `22, 22, 24` | `72, 65, 62, 82` | Secondary cards, grouped list backgrounds, reader HUD |

---

## 5. iOS Asset Catalog & Deployment

To guarantee that the new icon builds directly into the signed `.ipa` and displays on the physical iPhone Home Screen:

1. **Asset Catalog Location**: `Sources/YomiApp/Assets.xcassets/AppIcon.appiconset/`
   - Contains `AppIcon-1024.png` (universal unclipped master).
   - Contains `AppIcon-60@2x.png`, `AppIcon-60@3x.png`, `AppIcon-76@2x.png`, `AppIcon-83.5@2x.png`.
   - Wired via Apple standard `Contents.json`.
2. **Build Configuration**:
   - `c:\SIDEPROJECTS\yomi-ios\project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
   - `c:\SIDEPROJECTS\yomi-ios\Info.plist` defines `CFBundleIconName = AppIcon`.
3. **Packaging Behavior**:
   - XcodeGen and xcodebuild automatically compile `AppIcon.appiconset` into the binary payload.
   - Sideloadly preserves this asset catalog upon re-signing, ensuring the native squircle icon appears on iOS 17+.

---

## 6. Strict Anti-Patterns & Misuse Rules

- **Do NOT** place the mark inside a rounded box when submitting to the iOS App Store (`AppIcon-1024.png` must remain a full-bleed square; iOS handles squircle rounding automatically).
- **Do NOT** add arbitrary drop shadows, glowing neons, or multi-color rainbow gradients to the mark.
- **Do NOT** alter the $10\,\text{px}$ gutter spacing or deform the $111^{\circ}$ parallel diagonal angles.
- **Do NOT** set the wordmark in a standard system font; the letters in `final-horizontal.svg` are custom geometric vectors.
- **Do NOT** invert colors to light mode unless delivering paper print documentation.

---

## 7. Master File Directory Map

```
c:\SIDEPROJECTS\yomi-brand\
├── final-symbol.svg              # 100/100 Master vector mark (Black on transparent)
├── final-symbol-oled.svg         # 99/100 Master mark on True Black OLED
├── final-symbol-accent.svg       # 99/100 Electric Violet accent mark on OLED
├── final-horizontal.svg          # 98/100 Horizontal lockup (Symbol + YOMI wordmark)
├── AppIcon-1024.png              # 1024x1024 Unclipped App Store master
├── BRAND_GUIDELINES.md           # This document
│
├── Web & PWA Suite:
│   ├── favicon.ico               # 16/32/48 multi-resolution browser favicon
│   ├── favicon.svg               # Scalable vector favicon
│   ├── apple-touch-icon.png      # 180x180 iOS Safari bookmark icon
│   ├── icon-192.png              # Android / PWA standard
│   ├── icon-512.png              # Android / PWA splash
│   ├── maskable-512.png          # Android adaptive maskable icon
│   ├── site.webmanifest          # PWA metadata manifest
│   └── head-snippet.html         # HTML copy-paste code snippet
│
└── Variants Suite:
    ├── final-symbol-white.svg    # Transparent reversed white
    ├── final-symbol-black.svg    # Transparent pure black
    ├── final-symbol-mono-7c5cfc.svg # Single-hue brand violet
    └── [32/64/128/256/512/1024].png raster renders for all variants
```
