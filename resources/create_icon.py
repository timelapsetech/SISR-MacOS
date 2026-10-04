#!/usr/bin/env python3
"""Generate app icons from ``resources/icon-source.png``.

Writes:
  - ``resources/icons/icon_{size}x{size}.png``
  - ``resources/icon.icns`` (macOS; requires ``iconutil``)
  - ``SISR/Assets.xcassets/AppIcon.appiconset/``
  - ``docs/assets/favicon-32.png`` and ``docs/assets/icon-128.png``
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from typing import List, Tuple

from PIL import Image

# Repo root (parent of ``resources/``)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOURCE = os.path.join(REPO_ROOT, "resources", "icon-source.png")
ICONS_DIR = os.path.join(REPO_ROOT, "resources", "icons")
ICNS_OUT = os.path.join(REPO_ROOT, "resources", "icon.icns")
APPICONSET = os.path.join(
    REPO_ROOT, "SISR", "Assets.xcassets", "AppIcon.appiconset"
)
DOCS_ASSETS = os.path.join(REPO_ROOT, "docs", "assets")

# PNG sizes used for GUI + iconset source files (named icon_{w}x{h}.png in ``icons/``).
PNG_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# Maps Apple .iconset filename -> square size we generated (see PNG_SIZES).
ICONSET_MEMBERS: List[Tuple[str, int]] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

# AppIcon.appiconset filenames (Contents.json) -> pixel size.
APPICON_MEMBERS: List[Tuple[str, int]] = [
    ("icon_16x16.png", 16),
    ("icon_32x32.png", 32),
    ("icon_64x64.png", 64),
    ("icon_128x128.png", 128),
    ("icon_256x256.png", 256),
    ("icon_512x512.png", 512),
    ("icon_1024x1024.png", 1024),
]


def load_source() -> Image.Image:
    if not os.path.isfile(SOURCE):
        raise SystemExit(
            f"Missing master icon at {SOURCE}. Place a square PNG there and retry."
        )
    image = Image.open(SOURCE).convert("RGBA")
    if image.size[0] != image.size[1]:
        raise SystemExit(
            f"Master icon must be square; got {image.size[0]}x{image.size[1]}."
        )
    return fill_opaque_content(image)


def fill_opaque_content(image: Image.Image, alpha_threshold: int = 10) -> Image.Image:
    """Crop transparent padding and scale the artwork to fill the square canvas.

    Keeps the source dimensions; the opaque purple glyph is enlarged so its
    bounding box spans the full width/height (squircle corners may still be
    transparent).
    """
    alpha = image.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > alpha_threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise SystemExit(f"Master icon at {SOURCE} has no visible pixels.")

    left, top, right, bottom = bbox
    content = image.crop((left, top, right, bottom))
    side = max(content.size)
    # Tiny inset so Lanczos edge samples don't clip anti-aliased rim pixels.
    target = max(1, side)
    square = Image.new("RGBA", (target, target), (0, 0, 0, 0))
    ox = (target - content.size[0]) // 2
    oy = (target - content.size[1]) // 2
    square.paste(content, (ox, oy), content)

    canvas = image.size[0]
    if square.size != (canvas, canvas):
        square = square.resize((canvas, canvas), Image.Resampling.LANCZOS)
    return square


def resize_icon(source: Image.Image, size: int) -> Image.Image:
    if source.size == (size, size):
        return source.copy()
    return source.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    source = load_source()
    os.makedirs(ICONS_DIR, exist_ok=True)

    generated = {}
    for size in PNG_SIZES:
        icon = resize_icon(source, size)
        out = os.path.join(ICONS_DIR, f"icon_{size}x{size}.png")
        icon.save(out, format="PNG")
        generated[size] = out
        print(f"Wrote {out}")

    os.makedirs(APPICONSET, exist_ok=True)
    for name, size in APPICON_MEMBERS:
        dest = os.path.join(APPICONSET, name)
        shutil.copy2(generated[size], dest)
        print(f"Wrote {dest}")

    os.makedirs(DOCS_ASSETS, exist_ok=True)
    favicon = os.path.join(DOCS_ASSETS, "favicon-32.png")
    logo = os.path.join(DOCS_ASSETS, "icon-128.png")
    shutil.copy2(generated[32], favicon)
    shutil.copy2(generated[128], logo)
    print(f"Wrote {favicon}")
    print(f"Wrote {logo}")

    # Keep legacy icon.iconset in sync for tooling that still reads it.
    legacy_iconset = os.path.join(REPO_ROOT, "resources", "icon.iconset")
    shutil.rmtree(legacy_iconset, ignore_errors=True)
    os.makedirs(legacy_iconset, exist_ok=True)
    for name, size in ICONSET_MEMBERS:
        shutil.copy2(generated[size], os.path.join(legacy_iconset, name))

    if sys.platform != "darwin":
        print(
            "Skipping .icns (iconutil is macOS-only). On macOS run this script again."
        )
        return

    iconset = os.path.join(REPO_ROOT, "resources", "SISR.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset, exist_ok=True)

    for name, size in ICONSET_MEMBERS:
        src = generated[size]
        shutil.copy2(src, os.path.join(iconset, name))

    try:
        subprocess.run(
            ["iconutil", "-c", "icns", iconset, "-o", ICNS_OUT],
            check=True,
        )
    except FileNotFoundError:
        raise SystemExit(
            "iconutil not found; install Xcode command-line tools."
        ) from None

    print(f"Wrote {ICNS_OUT}")
    shutil.rmtree(iconset, ignore_errors=True)


if __name__ == "__main__":
    main()
