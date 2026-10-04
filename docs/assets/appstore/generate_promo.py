#!/usr/bin/env python3
"""Compose Mac App Store promotional screenshots from live SISR captures.

Outputs PNGs at 2880×1800, 2560×1600, and 1440×900 under promo/.
Uses real app UI (required for App Review) with marketing copy outside the window.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent
SHOTS = ROOT.parent / "screenshots"
OUT = ROOT / "promo"
ICON = ROOT.parent / "icon-128.png"

# App / site palette — graphite + teal (avoid purple / cream AI defaults)
BG_TOP = (14, 16, 20)
BG_BOTTOM = (8, 10, 14)
ACCENT = (45, 212, 191)  # teal
TEXT = (244, 244, 245)
MUTED = (161, 161, 170)
RULE = (45, 50, 58)
WINDOW_SHADOW = (0, 0, 0)

SIZES = [(2880, 1800), (2560, 1600), (1440, 900)]

SLIDES = [
    {
        "stem": "01-hero",
        "source": "01-main-workspace.png",
        "brand": True,
        "headline": "Turn photo sequences into video",
        "sub": "Open a numbered folder of stills. Preview, crop, grade, and render MP4, MOV, or GIF on your Mac.",
    },
    {
        "stem": "02-preview",
        "source": "02-playback-mid.png",
        "brand": False,
        "headline": "Preview every frame before you encode",
        "sub": "Scrub the filmstrip, set in and out points, and see crop and color updates live.",
    },
    {
        "stem": "03-grade",
        "source": "03-advanced-controls.png",
        "brand": False,
        "headline": "Crop, straighten, and color grade",
        "sub": "Interactive crop handles, precise numeric fields, and progressive controls that stay out of the way.",
    },
    {
        "stem": "04-export",
        "source": "06-bitrate-advanced.png",
        "brand": False,
        "headline": "Encode for 4K, HD, or social",
        "sub": "Landscape or portrait, auto bitrates sized for quality, or open Bitrate & quality to override.",
    },
    {
        "stem": "05-workflow",
        "source": "01-main-workspace.png",
        "brand": False,
        "headline": "Three steps to a finished video",
        "sub": "Open a numbered stills folder · Preview, crop, and grade · Render MP4, MOV, or GIF — built for timelapse and stop-motion.",
        "steps": ["Open sequence", "Frame & grade", "Render"],
    },
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    # SFNS is a solid system UI face; fall back through common Mac fonts.
    paths = [
        ("/System/Library/Fonts/SFNS.ttf", 0),
        ("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0),
        ("/System/Library/Fonts/Avenir Next.ttc", 1 if bold else 0),
        ("/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf", 0),
    ]
    for path, index in paths:
        try:
            return ImageFont.truetype(path, size=size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def vertical_gradient(size: tuple[int, int]) -> Image.Image:
    w, h = size
    base = Image.new("RGB", size, BG_BOTTOM)
    top = Image.new("RGB", size, BG_TOP)
    mask = Image.new("L", size, 0)
    md = ImageDraw.Draw(mask)
    for y in range(h):
        # Soft falloff; a bit more weight in the upper third for the headline band
        t = y / max(h - 1, 1)
        md.line([(0, y), (w, y)], fill=int(255 * (1.0 - t * 0.85)))
    return Image.composite(top, base, mask)


def radial_glow(size: tuple[int, int], color: tuple[int, int, int], center: tuple[float, float], radius: float, strength: float) -> Image.Image:
    w, h = size
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    cx, cy = int(center[0] * w), int(center[1] * h)
    r = int(radius * max(w, h))
    # Draw a soft disc then blur
    blob = Image.new("L", size, 0)
    bd = ImageDraw.Draw(blob)
    bd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=int(255 * strength))
    blob = blob.filter(ImageFilter.GaussianBlur(radius=r * 0.45))
    tint = Image.new("RGBA", size, color + (0,))
    tint.putalpha(blob)
    return Image.alpha_composite(overlay, tint)


def rounded_shadow(shot: Image.Image, radius: int, pad: int) -> Image.Image:
    """Return shot with rounded corners on a transparent canvas plus soft drop shadow."""
    w, h = shot.size
    # Rounded mask
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    rounded = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rounded.paste(shot.convert("RGBA"), (0, 0))
    rounded.putalpha(mask)

    canvas_w, canvas_h = w + pad * 2, h + pad * 2
    shadow = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sh_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(sh_mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=200)
    sh_layer = Image.new("RGBA", (w, h), (0, 0, 0, 180))
    sh_layer.putalpha(sh_mask)
    shadow.paste(sh_layer, (pad + 8, pad + 18), sh_layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=28))
    shadow.alpha_composite(rounded, (pad, pad))
    return shadow


def wrap_text(text: str, font: ImageFont.ImageFont, max_width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur: list[str] = []
    for word in words:
        trial = " ".join(cur + [word])
        if draw.textlength(trial, font=font) <= max_width:
            cur.append(word)
        else:
            if cur:
                lines.append(" ".join(cur))
            cur = [word]
    if cur:
        lines.append(" ".join(cur))
    return lines


def compose(slide: dict, width: int, height: int) -> Image.Image:
    scale = width / 2880
    canvas = vertical_gradient((width, height)).convert("RGBA")

    # Subtle teal atmosphere — not a loud glow
    glow = radial_glow((width, height), ACCENT, (0.5, 0.18), 0.55, 0.22)
    canvas = Image.alpha_composite(canvas, glow)
    glow2 = radial_glow((width, height), (37, 99, 235), (0.82, 0.75), 0.4, 0.10)  # faint cool depth
    canvas = Image.alpha_composite(canvas, glow2)

    draw = ImageDraw.Draw(canvas)

    # Typography sizes scale with canvas
    brand_size = max(22, int(34 * scale))
    head_size = max(36, int(72 * scale))
    sub_size = max(18, int(30 * scale))
    brand_font = load_font(brand_size, bold=True)
    head_font = load_font(head_size, bold=True)
    sub_font = load_font(sub_size, bold=False)

    margin_x = int(100 * scale)
    text_top = int(56 * scale)
    text_max_w = width - margin_x * 2

    y = text_top
    if slide.get("brand"):
        if ICON.exists():
            icon = Image.open(ICON).convert("RGBA")
            iw = int(52 * scale)
            icon = icon.resize((iw, iw), Image.Resampling.LANCZOS)
            canvas.paste(icon, (margin_x, y), icon)
            brand_x = margin_x + iw + int(16 * scale)
        else:
            brand_x = margin_x
        draw.text((brand_x, y + int(6 * scale)), "SISR", font=brand_font, fill=ACCENT)
        draw.text(
            (brand_x + draw.textlength("SISR", font=brand_font) + int(14 * scale), y + int(12 * scale)),
            "Simple Image Sequence Renderer",
            font=load_font(max(14, int(22 * scale)), bold=False),
            fill=MUTED,
        )
        y += int(62 * scale)
    else:
        draw.text((margin_x, y), "SISR", font=brand_font, fill=ACCENT)
        y += int(46 * scale)

    # Headline — slightly tighter leading so the product can be larger
    for line in wrap_text(slide["headline"], head_font, text_max_w, draw):
        draw.text((margin_x, y), line, font=head_font, fill=TEXT)
        y += int(head_size * 1.08)
    y += int(10 * scale)

    for line in wrap_text(slide["sub"], sub_font, int(text_max_w * 0.94), draw):
        draw.text((margin_x, y), line, font=sub_font, fill=MUTED)
        y += int(sub_size * 1.32)

    steps = slide.get("steps") or []
    if steps:
        y += int(20 * scale)
        step_font = load_font(max(15, int(24 * scale)), bold=True)
        num_font = load_font(max(14, int(22 * scale)), bold=True)
        x = margin_x
        for i, label in enumerate(steps, start=1):
            # Pill: number + label
            label_w = int(draw.textlength(label, font=step_font))
            pill_w = label_w + int(56 * scale)
            pill_h = int(40 * scale)
            draw.rounded_rectangle(
                (x, y, x + pill_w, y + pill_h),
                radius=int(pill_h / 2),
                fill=(24, 28, 34),
                outline=RULE,
                width=max(1, int(2 * scale)),
            )
            # number disc
            nd = int(28 * scale)
            nx = x + int(6 * scale)
            ny = y + (pill_h - nd) // 2
            draw.ellipse((nx, ny, nx + nd, ny + nd), fill=ACCENT)
            num = str(i)
            nw = draw.textlength(num, font=num_font)
            draw.text(
                (nx + (nd - nw) / 2, ny + int(3 * scale)),
                num,
                font=num_font,
                fill=(8, 12, 14),
            )
            draw.text(
                (nx + nd + int(10 * scale), y + int(8 * scale)),
                label,
                font=step_font,
                fill=TEXT,
            )
            x += pill_w + int(16 * scale)
        y += int(40 * scale)

    y += int(14 * scale)
    draw.rounded_rectangle(
        (margin_x, y, margin_x + int(64 * scale), y + max(3, int(4 * scale))),
        radius=2,
        fill=ACCENT,
    )
    copy_bottom = y + int(20 * scale)

    # Load and place screenshot in remaining space
    src_path = SHOTS / slide["source"]
    shot = Image.open(src_path).convert("RGB")
    # Mild contrast polish so the product reads crisp on the dark stage
    shot = ImageOps.autocontrast(shot, cutoff=0.4)

    avail_top = copy_bottom + int(8 * scale)
    avail_bottom = height - int(48 * scale)
    avail_h = max(200, avail_bottom - avail_top)
    avail_w = width - int(72 * scale)  # slightly wider product stage

    # Fit window into available box — prefer filling width for a larger product shot
    fit_scale = min(avail_w / shot.width, avail_h / shot.height) * 0.995
    nw, nh = int(shot.width * fit_scale), int(shot.height * fit_scale)
    shot_r = shot.resize((nw, nh), Image.Resampling.LANCZOS)

    radius = max(10, int(16 * scale))
    pad = max(20, int(36 * scale))
    framed = rounded_shadow(shot_r, radius=radius, pad=pad)

    fx = (width - framed.width) // 2
    # Prefer optically centering the window in the remaining band
    fy = avail_top + max(0, (avail_h - (framed.height - pad)) // 2) - pad // 3
    # Clamp so shadow isn't clipped awkwardly
    fy = min(max(fy, avail_top - pad // 2), height - framed.height - int(24 * scale))

    canvas.alpha_composite(framed, (fx, fy))

    return canvas.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for slide in SLIDES:
        if not (SHOTS / slide["source"]).exists():
            raise SystemExit(f"Missing source: {slide['source']}")
        for w, h in SIZES:
            img = compose(slide, w, h)
            out = OUT / f"{slide['stem']}-{w}x{h}.png"
            img.save(out, format="PNG", optimize=True)
            print(f"wrote {out.relative_to(ROOT.parent.parent)} ({out.stat().st_size // 1024} KB)")

    # Also write web-friendly JPEG previews of the 2880 set
    web = OUT / "web"
    web.mkdir(exist_ok=True)
    for slide in SLIDES:
        src = OUT / f"{slide['stem']}-2880x1800.png"
        im = Image.open(src)
        im.thumbnail((1440, 900), Image.Resampling.LANCZOS)
        im.convert("RGB").save(web / f"{slide['stem']}.jpg", quality=88, optimize=True)
    print(f"done → {OUT}")


if __name__ == "__main__":
    main()
