# Changelog

A running log of what each commit changed, newest first. Add a section with every commit.
Player-facing release notes live in `PATCH_NOTES.md` and `whats-new.js`.

---

## 2026-10-25 — Localization, in-app language picker, interstitial ad (v1.2, build 3)

### Added
- **8 new languages**: Romanian, Spanish (Mexico), Brazilian Portuguese, German, French, Japanese, Korean and Simplified Chinese.
  - `Localizable.xcstrings` (660 keys, every one translated, with plural forms for counted strings) and `InfoPlist.xcstrings` (app name and the tracking prompt).
  - New regions added to `knownRegions` in the project.
- **In-app language picker** (Settings → Language): "Device language" or any supported language, applied instantly without a restart.
  - New `Core/Localization.swift` (`AppLanguage`, `Bundle.app`).
  - `GameSettings.language`; `ContentView` re-renders and passes the chosen locale to SwiftUI.
  - Biome, bestiary and paint-job name tables rebuild when the language changes (`reloadNames()`).
  - "Reset to defaults" keeps the chosen language.
- **Interstitial ad** between runs, kept rare:
  - Shown only when leaving the results screen (Drill Again or Upgrade), never during a run.
  - Never with Remove Ads, never in a player's first 5 runs, at most one every 3 runs (the count resets each launch), and at least 4 minutes after any full-screen ad.
  - Never waits: if no ad is loaded, the game continues at once.
  - Tunable in `AdConfig` (`interstitialFreeRuns`, `interstitialEveryRuns`, `interstitialGap`). Debug builds use Google's test unit.
- `whats-new.js`: v1.2 "What's New" text in all 9 App Store locales.

### Changed
- Every user-facing string goes through `String(localized:bundle: .app)`, with whole-sentence format strings so word order can change per language.
- Layout fixes for long translations: screen titles shrink to fit, rarity tags never break mid-word, part names wrap to two lines, and the renderer measures in-game text (including CJK) instead of assuming widths.
- Boss intro banner uses a per-biome "Guardian of …" line; biome-specific generation keys off the layer index, not the localized name.
- Daily challenge date follows the chosen language.
- `AdsManager`: the rewarded delegate became a shared `FullScreenDelegate`, and the manager now records when the last full-screen ad closed.

### Docs
- `PATCH_NOTES.md`: v1.2 section.
- `APP_STORE_LISTING.md`, `PRIVACY_POLICY.md` and `PRIVACY_POLICY_GoogleSites.html`: describe the occasional between-runs ad and that Remove Ads removes all ads.
- `CLAUDE.md`: a localization section and the interstitial rules.
