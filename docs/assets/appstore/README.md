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
| `06-feature-cards` | Feature callouts + App Store badge | Create timelapses with crop, grade, and hi-res export |
| `07-annotated-ui` | Annotated workspace tour | Easy import, precise cropping, fast 4K export |

`06` / `07` come from hand-designed marketing graphics (sources in `sources/`), letterboxed to 16:10.

### Sizes

For each stem:

- `*-2880x1800.png` — preferred Mac App Store size
- `*-2560x1600.png`
- `*-1440x900.png`
- `*-1280x800.png` — also accepted by App Store Connect (`06`/`07` include this)

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
