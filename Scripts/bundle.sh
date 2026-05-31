#!/usr/bin/env bash
# Builds baka and assembles a runnable macOS .app bundle.
#
# Usage: ./Scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="baka"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "!! Built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# App icon: regenerate from the source logo if available, else use committed icns.
ICON_SRC="/Users/purrweb/Desktop/lo.jpg"
if [[ -f "$ICON_SRC" ]] && command -v python3 >/dev/null; then
    python3 "$ROOT/Scripts/make_icon.py" "$ICON_SRC" "$ROOT/Resources/AppIcon.icns" >/dev/null 2>&1 || true
fi
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc sign so the binary runs and can use the network without a dev cert.
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "   (codesign skipped — running unsigned)"

echo "==> Done: $APP_DIR"
echo "    Run with: open \"$APP_DIR\"   (or)   \"$CONTENTS/MacOS/$APP_NAME\""
