# Changelog

All notable changes to Baka are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.4] — 2026-06-01

### Fixed
- Workshop content is now discovered from **both** locations it can live in —
  the standard Steam folder (`~/Library/Application Support/Steam/…`) and Baka's
  own SteamCMD directory — so downloads and already-subscribed items are found
  regardless of where they landed.

## [0.1.3] — 2026-06-01

### Added
- **Live preview** — tapping a wallpaper opens a large, playing preview so you
  see exactly how it looks before applying it (with a per-monitor target picker).

### Fixed
- **Workshop downloads now appear in the library.** SteamCMD on macOS writes
  workshop content to the standard Steam path (`~/Library/Application
  Support/Steam/...`), not our install dir — Baka now reads the exact path from
  SteamCMD's output and checks both locations, so downloaded wallpapers install
  correctly.

## [0.1.2] — 2026-06-01

### Added
- **Real in-app auto-update.** "Обновиться сейчас" now downloads the release,
  swaps the app bundle in place, and relaunches automatically — no more manual
  unzip-and-replace. Falls back to opening the download if it can't write the
  bundle (e.g. running in dev or from a read-only location).

## [0.1.1] — 2026-06-01

### Fixed
- Release builds now compile against the **macOS 26 SDK** (CI moved to the
  `macos-26` runner with Xcode 26), so the downloaded app uses the same native
  design as a local build instead of the legacy macOS 15 appearance.

### Changed
- App icon and the **Baka** wordmark + version now live at the top of Settings
  (centered), not in the sidebar.

## [0.1.0] — 2026-06-01

The first public build of Baka — native animated wallpapers for macOS.

### Added
- **Animated wallpapers** rendered behind the desktop icons, one per display.
  - Video wallpapers (`mp4`, `mov`, `m4v`, `webm`) via hardware-decoded AVFoundation.
  - Web/WebGL wallpapers via WKWebView with an injected frame-rate cap.
- **Multi-monitor** support with per-display assignment that survives reconnects
  (stable display keys derived from vendor/model/serial).
- **Battery & performance governor** — pauses or throttles rendering on battery,
  in Low Power Mode, when covered by a fullscreen app, on display sleep, or on
  screen lock. Configurable per-condition.
- **Steam Workshop browser** for Wallpaper Engine (app `431960`):
  - Flexible filters: type, sort, trend period, multi-select genres, resolution,
    and a three-state 18+ control (hide / show / only).
  - Fast cached thumbnails.
- **Downloads** via SteamCMD (auto-installed) using your own Steam account that
  owns Wallpaper Engine, with a batched single-login queue and a progress tab.
  Instant import from a local Steam install when the item is already subscribed.
- **In-app updates** — checks GitHub Releases, shows release notes, and offers
  *update now / next time / skip this version*.
- A native macOS app icon and menu-bar presence.

### Notes
- Wallpaper Engine's proprietary **Scene** (`.pkg`) format is intentionally
  unsupported — only portable Video and Web wallpapers render.
