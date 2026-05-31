#!/usr/bin/env python3
"""Generate a macOS-style AppIcon.icns from an arbitrary source image.

Follows Apple's macOS template proportions: the artwork sits in an 824x824
rounded-rect inside a 1024 canvas (≈100px margin) with a continuous-corner
squircle mask and a soft drop shadow, so a rectangular/photo source looks like
a native macOS icon rather than a raw screenshot.

Usage: make_icon.py <source-image> <output.icns>
"""
import sys
import subprocess
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
ART = 824                      # Apple macOS art rect
MARGIN = (CANVAS - ART) // 2
RADIUS = int(ART * 0.225)      # approximates the continuous squircle corner


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def center_square(img: Image.Image) -> Image.Image:
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left + side, top + side))


def build_master(src: Path) -> Image.Image:
    art = center_square(Image.open(src).convert("RGB")).resize((ART, ART), Image.LANCZOS)
    art = art.convert("RGBA")
    art.putalpha(rounded_mask(ART, RADIUS))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # Soft drop shadow beneath the art tile.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        [MARGIN, MARGIN + 14, MARGIN + ART, MARGIN + ART + 14],
        radius=RADIUS, fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas = Image.alpha_composite(canvas, shadow)

    canvas.paste(art, (MARGIN, MARGIN), art)
    return canvas


def make_icns(master: Image.Image, output: Path) -> None:
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for s in sizes:
            img = master.resize((s, s), Image.LANCZOS)
            if s <= 512:
                img.save(iconset / f"icon_{s}x{s}.png")
            if s >= 32:
                half = s // 2
                img.save(iconset / f"icon_{half}x{half}@2x.png")
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(output)],
            check=True,
        )


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    make_icns(build_master(src), out)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
