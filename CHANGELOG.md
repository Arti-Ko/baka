# Changelog

All notable changes to Baka are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.1] — 2026-06-01

### Added
- **Browse by author** — right-click a wallpaper (in the Workshop or your
  library) → "Другие обои от автора" to see only that creator's wallpapers,
  with a banner and a "show all" reset.

### Changed
- The "Удалить весь контент" reset button is now red.

## [0.2.0] — 2026-06-01

### Added
- **Audio control** — a per-wallpaper volume slider (0–100%) in the preview,
  saved with the wallpaper. Video uses real volume; web scales HTML5 media. A
  master "mute all" switch remains in Settings.
- **Reset button** in Settings — removes every wallpaper, all downloaded/
  imported content, and clears monitor assignments (keeps settings + Steam
  login), with a confirmation dialog.

### Fixed
- **Auto-update no longer launches a second copy.** The app now exits hard
  before the swap (a presented sheet could delay `NSApp.terminate`, leaving the
  old process alive), and the worker force-quits a lingering instance and
  relaunches without `-n`, guaranteeing a single running app.

## [0.1.9] — 2026-06-01

### Added
- **Video player in the preview** — video wallpapers now open in a native
  player with a timeline scrubber and play/pause, so you can seek through the
  clip. Speed still applies (drives the player rate); the clip loops.
- **Mixed Video + Web results** — the Workshop type filter gained an **«Оба»**
  option that fetches both types and interleaves them in one feed.

## [0.1.8] — 2026-06-01

### Fixed
- **Auto-update now relaunches reliably.** The updater downloaded the new build
  but sometimes failed to restart into it. The swap-and-relaunch worker is now
  fully detached (`nohup` + double-fork) so it survives the app quitting, waits
  for the process to exit, retries the relaunch, and writes a log to
  `~/Library/Application Support/baka/update.log` for diagnosis.

## [0.1.7] — 2026-06-01

### Changed
- Version is now shown cleanly as `v0.1.7` (dropped the build number in
  parentheses).

## [0.1.6] — 2026-06-01

### Added
- **Playback speed** in the preview — a slider from 0 to 1000% (100% = normal,
  up to 10×), applied live and saved per wallpaper. Video uses real rate; web
  scales any HTML5 `<video>` playback.
- **Multi-monitor apply** — choose any combination of connected displays (or
  "select all") in the preview; apply puts the wallpaper on exactly the chosen
  screens and clears it from deselected ones.
- **Infinite scroll** in the Workshop — pages now load automatically as you
  scroll instead of a "load more" button, with an "all results" end marker.

## [0.1.5] — 2026-06-01

### Added
- **Update progress bar.** The update dialog now shows a live percentage and
  phase (Скачивание % → Распаковка → Установка → Перезапуск), so it's clear the
  update is working and not frozen.

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
