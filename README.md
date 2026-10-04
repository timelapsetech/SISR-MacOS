![SISR App Icon](resources/icons/icon_128x128.png)

# SISR for macOS

**Simple Image Sequence Renderer** — a native Mac app for turning numbered photo sequences into MP4, MOV, or GIF.

**Version:** 1.0.3

Open a folder of stills, preview on a filmstrip, crop and grade interactively, then encode with Core Image + AVFoundation (no FFmpeg).

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ to build from source (Xcode 16 recommended)

## Download

Get a notarized build from [GitHub Releases](https://github.com/timelapsetech/SISR-MacOS/releases) (`SISR-native-*-macos-universal.zip`), or build from source below.

User docs: [docs/](docs/index.html) (guide, crops, privacy, support).

## Open & run

```bash
make run
```

Or:

```bash
python3 scripts/generate_xcodeproj.py
open SISR.xcodeproj
```

In Xcode: select the **SISR** scheme → Run (⌘R).

### Package tests

```bash
make test
```

## Layout

| Path | Role |
|------|------|
| `SISR/` | SwiftUI app (three-panel UI, dark-mode theme) |
| `Packages/SISRKit/` | Sequence scanning, EXIF dates, crop/pipeline, AVFoundation/GIF render |
| `project.yml` | Optional XcodeGen spec |
| `scripts/generate_xcodeproj.py` | Checked-in generator for `SISR.xcodeproj` |
| `docs/` | Product site (GitHub Pages–ready) |
| `resources/` | Icon source and generated icon assets |

## Features

- Source / Output / Overlay sidebar
- Center viewer + filmstrip timeline with in/out points, J/K/L, I/O
- Inspector: crop with aspect lock & resolution checks, transform, color, detail, deflicker
- Codecs: H.264, HEVC, ProRes, ProRes HQ, GIF
- Live render progress (sidebar card, toolbar, Dock badge, notification)
- Per-sequence state autosave; security-scoped bookmarks; Open Recent

## Release

See [scripts/release/README.md](scripts/release/README.md). Tag with `app-v*` (e.g. `app-v1.0.3`) to build, notarize, and attach a universal zip.

## License

MIT — see [LICENSE](LICENSE).
