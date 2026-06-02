<div align="center">

<img src="docs/baka-icon.png" width="128" alt="Baka app icon" />

# Baka

### Animated live wallpapers for macOS — native, fast, battery-aware.

A Wallpaper Engine–style experience built **only** for macOS, with a native
SwiftUI interface, hardware-accelerated rendering, and a serious focus on
not wrecking your battery.

[![CI](https://github.com/Arti-Ko/baka/actions/workflows/ci.yml/badge.svg)](https://github.com/Arti-Ko/baka/actions/workflows/ci.yml)
[![Release](https://github.com/Arti-Ko/baka/actions/workflows/release.yml/badge.svg)](https://github.com/Arti-Ko/baka/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## ✨ Features

- 🎬 **Video & Web wallpapers** — `mp4 / mov / m4v / webm` decoded on the GPU via
  AVFoundation, plus HTML/WebGL wallpapers in WKWebView.
- 🧩 **Native Scene rendering** — Baka unpacks WE's `.pkg`, decodes `.tex`
  textures (incl. DXT1/3/5 block compression), and composites a scene's image
  layers natively (position, scale, rotation, opacity, z-order) with **pointer
  depth-parallax** and **particle systems** (snow, dust, embers via
  `CAEmitterLayer`). Shaders and scripted animation aren't rendered yet, and
  anything it can't composite falls back to a poster.
- 🖼️ **Application (poster mode)** — Windows `.exe` wallpapers can't run on
  macOS, so Baka renders their bundled preview (animated GIF or still) as a
  poster instead of failing.
- 🖥️ **True multi-monitor** — a different wallpaper per display, with assignments
  that survive reconnects and resolution changes.
- 🔋 **Battery-first** — a power governor pauses or throttles motion based on real
  conditions instead of burning your laptop.
- 🛰️ **Steam Workshop browser** — search Wallpaper Engine's workshop with rich
  filters and download wallpapers you own straight into your library.
- 🎚️ **Flexible filters** — type, sort, trend window, multi-select genres,
  resolution, and a three-state **18+** control (hide / show / only).
- ⬇️ **Download queue** — batched SteamCMD downloads with a live progress tab.
- 🔄 **In-app updates** — release notes + *update now / later / skip*.
- 🍎 **Feels native** — SwiftUI throughout, a menu-bar item, and a real app icon.

---

## 🔋 Battery & performance

Baka's `PowerGovernor` decides how wallpapers render **right now**:

| Condition | Default behavior |
| --- | --- |
| On battery | **Pause** (or throttle FPS / full speed — your choice) |
| Low Power Mode | Pause |
| Covered by a fullscreen app | Pause (driven by window occlusion — essentially free) |
| Display asleep / screen locked | Pause |
| On AC power, visible | Play (optional FPS cap) |

Paused wallpapers release decode and GPU work entirely. Video uses hardware
decode; web wallpapers honor an injected `requestAnimationFrame` cap and fully
stop when paused.

---

## 📦 Install

1. Download **`Baka-macos.zip`** from the [latest release](https://github.com/Arti-Ko/baka/releases/latest).
2. Unzip and move **Baka.app** to `/Applications`.
3. First launch: right-click → **Open** (the build is ad-hoc signed, not notarized).

> Requires macOS 14 (Sonoma) or newer, Apple Silicon or Intel.

---

## 🛠️ Build from source

```bash
git clone https://github.com/Arti-Ko/baka.git
cd baka

# Run in development
swift run baka

# Or build a distributable .app bundle
./Scripts/bundle.sh release
open dist/baka.app
```

Requires the **Swift 6** toolchain (Xcode 16+).

---

## 🛰️ Steam Workshop — how downloading works

Baka browses Wallpaper Engine's workshop (Steam app `431960`) and downloads the
items **you own**, using Valve's official **SteamCMD** (installed automatically
on first use).

1. **Settings → Steam / Wallpaper Engine → Log in.** Use the account that owns
   Wallpaper Engine. A Steam Guard code is requested once; the machine is then
   trusted.
2. Browse the **Workshop** tab, hit **Download** — items are fetched in a single
   batched SteamCMD session and added to your library.
3. If you already have Steam + Wallpaper Engine installed and are subscribed to
   an item, Baka imports it **instantly** from the local Steam folder.

**Honest limitations**

- Wallpaper Engine's **Scene** (`.pkg`) format is rendered natively: Baka unpacks
  the package, decodes `.tex` textures (FreeImage/RGBA/LZ4 **and DXT1/3/5 block
  compression**), composites the image layers, applies pointer depth-parallax,
  and renders particle systems via `CAEmitterLayer`. **Not yet supported:**
  shaders, scripted property animation, and audio-reactive effects — scenes
  relying on those look partial or fall back to a poster. **Application**
  (`.exe`) wallpapers are Windows executables and only ever show as a poster.
  Portable **Video** and **Web** wallpapers render live and in full.
- SteamCMD requires **Rosetta** on Apple Silicon (`softwareupdate --install-rosetta`).
- Credentials are stored locally in a `0600` file and used only to log into Steam.

---

## 🏗️ Architecture

```
App/         BakaApp (@main), AppDelegate, AppState (composition root)
Wallpaper/   Desktop-level NSWindow, video/web renderers, controller
Power/       PowerSourceMonitor (IOKit), PowerGovernor, PowerPolicy
Screens/     Multi-monitor manager (stable keys, hotplug)
Library/     Wallpaper model, catalog, importer
  Workshop/  Steam client, SteamCMD, download manager, project.json parser
  Update/    GitHub release update checker
UI/          SwiftUI views (library, monitors, workshop, downloads, settings)
Util/        Logging, paths, versioning, credential storage
```

**Data flow:** system & power events → `PowerGovernor` emits a `RenderDirective`
→ `WallpaperController` fans it out to one `WallpaperWindow` per screen → each
window combines it with its own occlusion state before driving its renderer.

---

## 🚀 Releases & CI

- Every push/PR is built and tested on macOS via GitHub Actions.
- Pushing a tag `vX.Y.Z` builds the app, zips it, and publishes a GitHub Release
  with auto-generated notes — which the in-app updater then surfaces.

```bash
# cut a release
git tag v0.2.0
git push origin v0.2.0
```

---

## 📄 License

[MIT](LICENSE) — do what you like, no warranty.

> Baka does not host or redistribute any wallpapers. All Workshop content
> belongs to its respective creators and is delivered through Steam.
