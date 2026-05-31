# Changelog

All notable changes to Baka are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

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
