# App Store screenshots

## Upload these (promotional)

**`promo/`** — captioned marketing canvases built from live captures of the native app.

| File stem | Message | Suggested App Store Connect caption |
|-----------|---------|-------------------------------------|
| `01-hero` | Brand + value prop | Turn photo sequences into video |
| `02-preview` | Filmstrip / in-out | Preview every frame before you encode |
| `03-grade` | Crop + color | Crop, straighten, and color grade |
| `04-export` | Format / bitrate | Encode for 4K, HD, or social |
| `05-workflow` | Three-step flow | Open → frame & grade → render |

### Sizes

For each stem:

- `*-2880x1800.png` — preferred Mac App Store size
- `*-2560x1600.png`
- `*-1440x900.png`

Upload one size set consistently (prefer **2880×1800** when Connect offers it).

### App Review notes

- Screenshots show **real SISR UI** (not mock chrome).
- Marketing text sits **outside** the app window.
- No pricing, rankings, “#1”, or competitor claims.
- Copy matches actual features (sequence folders → MP4/MOV/GIF).

### Regenerate

```bash
cd docs/assets/appstore
python3 generate_promo.py
```

Sources: `../screenshots/*.png`. Web JPEG previews: `promo/web/`.

## Plain window canvases (optional)

The numbered files in this folder (`01-workspace-*`, etc.) are uncaptioned window-on-canvas shots if you prefer minimal screenshots in Connect.
