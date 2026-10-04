# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Render test coverage** in SISRKit: FramePipeline pixel checks (crop, orientation, overlay opacity, grade, preview flags) plus tiny encode smokes for every codec, in/out + date overlay, and deflicker.

## [1.0.4] - 2026-10-04

### Fixed
- **Overlay background opacity** in encodes now matches the viewer burn-in preview. The plate is composited with Core Graphics (gamma-encoded source-over) instead of Core Image’s linear `composited(over:)`, which made the same alpha look washed out.
- **RenderController concurrency warnings** — notification auth uses async `UserNotifications` APIs on the main actor; render task capture list no longer mixes weak/strong `self`.

## [1.0.3] - 2026-10-04

### Added
- **Native size** and **Scale to fit** full-frame shortcuts: render at source pixels, or shrink the full frame to a max width/height with no cropping.
- **Transform 90° chips** (0° / 90° / 180° / 270°) plus free **Angle** entry for any degree of fine rotation.
- **Overlay burn-in preview** inside the crop on the viewer, plus a **Background** opacity control (default 50%) that matches the final encode.
- **Preview full** at the top of the inspector: aspect-fits the cropped output (with burn-in) as large as possible in the viewer so you can inspect what the encode will look like.
- **Timeline zoom** — fit-by-default filmstrip with pinch / − Fit + controls; zoomed-out views sample frames so thumbs stay readable; zoom in to scroll frame-by-frame.
- **Go to Start / In / Out / End** transport controls (Home, ⇧I, ⇧O, End).
- **Play In to Out** (⇧Space) to preview only the marked range.
- **J / K / L** shuttle reverse, stop, and shuttle forward (repeat J/L to speed up).

### Changed
- **Play** runs the full sequence from the current playhead and ignores In/Out; at the last frame it wraps to the start.
- **Output size** lives entirely in the right inspector (all presets); the left Format section was removed.
- **Render destination** no longer defaults to the image-sequence folder; if unset, Render prompts for an output folder first.
- **Scale to fit** never upscales — max width/height act as a ceiling only.
- **Viewer playback** uses cached downscaled frames while playing (with forward prefetch) and applies the full graded preview when paused; playhead autosave and filmstrip decode are skipped during play for smoother scrubbing.

### Fixed
- **90° / 270° preview stretch** — viewer and crop overlay now fit the oriented (swapped) frame instead of the original landscape size.
- **Overlay background opacity** in renders now matches the viewer preview (transparent plate was blending against an uncleared buffer and looking too light).
- **Crop-mode crash** when source size was invalid (NaN → Int) — geometry helpers now harden zero/invalid sizes.

## [1.0.2] - 2026-10-03

### Added
- **App Store promotional screenshots** in `docs/assets/appstore/promo/`: captioned 2880×1800 / 2560×1600 / 1440×900 canvases (hero, preview, grade, export, workflow) generated from live UI captures, plus `generate_promo.py` to regenerate.

## [1.0.1] - 2026-10-03

### Added
- **Docs site** with homepage screenshots, detailed user guide, App Store–oriented `privacy.html` / `support.html`, and marketing canvases under `docs/assets/appstore/`.
- **App Store compliance**: `ITSAppUsesNonExemptEncryption`, `PrivacyInfo.xcprivacy` (UserDefaults + file timestamps), Help menu and Settings links to guide / support / privacy.
- **Open / Close** in the sequence sidebar, plus clearer empty-state flow.
- **Numeric fields** alongside straighten and color sliders for precise values.
- **Bitrate & quality** progressive disclosure with auto Mbps targets for 1080p / 4K and manual overrides.
- **Settings toggle** for “Notify when render finishes” (permission requested at most once).

### Changed
- **Inspector progressive disclosure**: color adjustments grouped under one disclosure; align/zoom, resolution fitness, flips, and sharpen/noise/vignette stay collapsed until needed.
- **H.264 bitrate ladder** and encode path tuned for Instagram-friendly quality without excessive render memory use.
- **Deflicker analysis** reports per-frame progress instead of appearing stuck at 0%.

### Fixed
- **Straighten** preview vs render sign mismatch (Core Image rotation direction).
- **Sandbox overwrite / remove** failures when replacing an existing render (security-scoped bookmarks and unique sibling fallback).
- **FrameCache QoS** priority inversions that could stall preview decode under load.
- **Upscale / resolution fitness** warnings when output exceeds native crop coverage.
- **CLI `--open` / bare-path open** limited to Debug builds so Release/App Store sandboxed launches rely on Open panel / Finder.

## [1.0.0] - 2026-10-03

### Added
- **Native macOS app (SwiftUI)**: three-panel layout with scrubbable preview, timeline in/out points, interactive crop/transform/color, and Core Image + AVFoundation/GIF export (no FFmpeg). Dark-mode-first UI.
- **Release pipeline**: `.github/workflows/release-macos.yml` and `scripts/release/macos-swift-build-sign-notarize.sh` for `app-v*` tags.
