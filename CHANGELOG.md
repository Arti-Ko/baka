# Changelog

All notable changes to Baka are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-06-02

### Added
- **Scene & Application support (poster mode).** Wallpaper Engine's proprietary
  Scene (`.pkg`) and Application (`.exe`) wallpapers can't run natively on macOS,
  but they are no longer dead ends: Baka now renders their bundled preview
  (animated GIF or still image) as a "poster" wallpaper. They are browseable,
  downloadable, assignable to monitors, and tagged with `SCENE` / `APP` badges.
- **Scene / App filters** in the Workshop type picker, alongside Видео+Web.

### Fixed
- **Far fewer download errors.** Scene/Application items used to fail with
  "формат не поддерживается"; they now install as posters instead. Items that
  bundle a real video/HTML are still salvaged and rendered live.
- **No more main-thread stalls during install.** Preview/thumbnail downloads
  were done with a blocking `Data(contentsOf:)` on the main actor (a UI freeze
  risk); they now use async `URLSession`.
- **Robust content path resolution.** The installer rebuilt the on-disk content
  path with a fragile string replace that broke under symlinked roots
  (`/var` → `/private/var`), producing spurious "контент не найден" failures. It
  now remaps paths component-wise (symlink-safe).

## [0.2.4] — 2026-06-01

### Added
- **Cancel downloads** — each active download in the Downloads tab has a cancel
  button. Queued items are dropped; an in-progress item stops the SteamCMD
  process, and any other items in the same batch resume automatically.

## [0.2.3] — 2026-06-01

### Added
- **Real download progress** — the Downloads tab now shows a percentage bar with
  live status ("SteamCMD · 42% · 54 MB из 128 MB"), parsed from SteamCMD's output.
- **Wallpaper size** is shown on Workshop cards and in the Downloads list.

## [0.2.2] — 2026-06-01

### Fixed
- **Quit now actually quits.** An active wallpaper (AVPlayer/WKWebView) could
  keep the process alive, requiring Force Quit. On termination the app now tears
  down all wallpaper windows and hard-exits.
- **Download errors no longer say "OK".** Failed SteamCMD downloads now show a
  meaningful error line instead of trailing log noise.

### Added
- **Downloads persist and are retryable.** Failed and unfinished downloads stay
  in the Downloads tab (and survive restarts) instead of vanishing; unfinished
  ones resume on launch, and failed ones get a **Повторить** (retry) button and
  a dismiss action.

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
