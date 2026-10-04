import AppKit
import SwiftUI
import SISRKit

struct ViewerView: View {
    @Bindable var project: SequenceProject
    var frameCache: FrameCache
    var playback: PlaybackController

    @State private var compositionImage: NSImage?
    @State private var debounce: Task<Void, Never>?
    @State private var previewEpoch: UInt64 = 0
    @State private var frameURLs: [URL] = []

    private let contentInset: CGFloat = 12

    private var previewOutputFull: Bool {
        project.previewOutputFull && !project.showOriginal
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.viewerCanvas

                if project.hasSequence {
                    GeometryReader { inner in
                        // Composition: oriented source. Preview full / Original: output or raw size.
                        let displaySize: CGSize = {
                            if project.showOriginal {
                                return project.sourceSize
                            }
                            if previewOutputFull {
                                return project.outputPixelSize.cgSize
                            }
                            return project.orientedSourceSize
                        }()
                        let fitted = CropOverlayView.fittedImageRect(
                            sourceSize: displaySize,
                            in: inner.size
                        )
                        let cropNorm = project.crop.normalizedRect
                        let coverScale = straightenCoverScale
                        let anchor = UnitPoint(x: cropNorm.midX, y: cropNorm.midY)

                        ZStack {
                            if let compositionImage {
                                Image(nsImage: compositionImage)
                                    .resizable()
                                    .interpolation(playback.isPlaying ? .medium : .high)
                                    .frame(width: fitted.width, height: fitted.height)
                                    .modifier(CompositionStraightenModifier(
                                        enabled: !previewOutputFull && !project.showOriginal,
                                        degrees: -project.crop.straightenDegrees,
                                        coverScale: coverScale,
                                        anchor: anchor,
                                        clipSize: fitted.size
                                    ))
                                    .position(x: fitted.midX, y: fitted.midY)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            if previewOutputFull {
                                // SwiftUI burn-in matches composition opacity; not baked into pixels.
                                BurnInOverlayPreview(project: project, cropRect: fitted)
                            } else if !project.showOriginal {
                                CropOverlayView(project: project)
                            }
                        }
                    }
                    .padding(contentInset)
                } else {
                    EmptyStateView {
                        NotificationCenter.default.post(name: .sisrOpenSequence, object: nil)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .focusable()
            .onKeyPress(keys: [.init("j"), .init("J")]) { _ in
                playback.shuttle(project: project, direction: -1)
                return .handled
            }
            .onKeyPress(keys: [.init("k"), .init("K")]) { _ in
                playback.shuttle(project: project, direction: 0)
                return .handled
            }
            .onKeyPress(keys: [.init("l"), .init("L")]) { _ in
                playback.shuttle(project: project, direction: 1)
                return .handled
            }
            .onKeyPress(keys: [.init("\\")]) { _ in
                project.showOriginal.toggle()
                if project.showOriginal {
                    project.previewOutputFull = false
                }
                return .handled
            }
            .onChange(of: project.playheadIndex) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.crop.flipHorizontal) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.crop.flipVertical) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.crop.rotationQuarterTurns) { _, _ in refreshPreview(in: geo.size) }
            // Crop box / straighten are SwiftUI-only in composition mode; re-bake when previewing output.
            .onChange(of: project.crop.normalizedRect) { _, _ in
                guard project.previewOutputFull else { return }
                refreshPreview(in: geo.size)
            }
            .onChange(of: project.crop.straightenDegrees) { _, _ in
                guard project.previewOutputFull else { return }
                refreshPreview(in: geo.size)
            }
            .onChange(of: project.adjustments) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.showOriginal) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.previewOutputFull) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.render.preset) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.render.customSize) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.render.maxWidth) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.render.maxHeight) { _, _ in refreshPreview(in: geo.size) }
            .onChange(of: project.sequence?.directory.path) { _, _ in
                frameURLs = project.sequence?.frames.map(\.url) ?? []
                refreshPreview(in: geo.size)
            }
            .onChange(of: playback.isPlaying) { _, playing in
                // When playback stops, upgrade the current frame to a graded preview.
                if !playing {
                    refreshPreview(in: geo.size)
                }
            }
            .onAppear {
                frameURLs = project.sequence?.frames.map(\.url) ?? []
                refreshPreview(in: geo.size)
            }
        }
    }

    /// Zoom only when the crop is near an edge and rotation would sample outside the image.
    private var straightenCoverScale: CGFloat {
        let size = project.orientedSourceSize
        guard size.width > 0 else { return 1 }
        let pixel = project.crop.pixelRect(sourceSize: size)
        return StraightenGeometry.coverScale(
            sourceSize: size,
            cropRect: pixel,
            degrees: project.crop.straightenDegrees
        )
    }

    private func refreshPreview(in size: CGSize) {
        debounce?.cancel()
        previewEpoch &+= 1
        let epoch = previewEpoch
        let playing = playback.isPlaying
        let bakeOutput = previewOutputFull

        debounce = Task { @MainActor in
            if bakeOutput {
                // Same strategy as composition: thumb crop while playing; grade when paused.
                await updateFastOutputPreview(viewSize: size, epoch: epoch)
                if playing { return }
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled, epoch == previewEpoch, !playback.isPlaying else { return }
                await updateGradedPreview(viewSize: size, epoch: epoch)
                return
            }

            if playing {
                await updateFastPreview(viewSize: size, epoch: epoch)
                return
            }

            // Show a thumbnail immediately, then grade after a short settle.
            await updateFastPreview(viewSize: size, epoch: epoch)
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled, epoch == previewEpoch, !playback.isPlaying else { return }
            await updateGradedPreview(viewSize: size, epoch: epoch)
        }
    }

    @MainActor
    private func updateFastPreview(viewSize: CGSize, epoch: UInt64) async {
        guard epoch == previewEpoch,
              let sequence = project.sequence,
              sequence.frames.indices.contains(project.playheadIndex)
        else {
            if epoch == previewEpoch { compositionImage = nil }
            return
        }

        let frame = sequence.frames[project.playheadIndex]
        let maxPixel = previewMaxPixel(for: viewSize, playing: playback.isPlaying)
        prefetchAroundPlayhead(sequence: sequence, maxPixel: maxPixel)

        guard let thumb = await loadThumbnail(for: frame.url, maxPixel: maxPixel, epoch: epoch) else {
            return
        }

        if project.showOriginal {
            compositionImage = thumb
            return
        }

        let crop = project.crop
        let needsOrient =
            crop.flipHorizontal
            || crop.flipVertical
            || (((crop.rotationQuarterTurns % 4) + 4) % 4) != 0
        guard needsOrient else {
            compositionImage = thumb
            return
        }

        let oriented = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return thumb
            }
            let pipeline = FramePipeline()
            guard let out = pipeline.orientPreview(cg, crop: crop) else { return thumb }
            return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
        }.value

        guard epoch == previewEpoch else { return }
        compositionImage = oriented ?? thumb
    }

    /// Preview Full fast path: crop/scale cached thumbs to output aspect (no grade; overlay in SwiftUI).
    @MainActor
    private func updateFastOutputPreview(viewSize: CGSize, epoch: UInt64) async {
        guard epoch == previewEpoch,
              let sequence = project.sequence,
              sequence.frames.indices.contains(project.playheadIndex)
        else {
            if epoch == previewEpoch { compositionImage = nil }
            return
        }

        let frame = sequence.frames[project.playheadIndex]
        let maxPixel = previewMaxPixel(for: viewSize, playing: playback.isPlaying)
        let previewSize = previewPixelSize(output: project.outputPixelSize, maxPixel: maxPixel)
        let crop = project.crop
        prefetchAroundPlayhead(sequence: sequence, maxPixel: maxPixel)

        guard let thumb = await loadThumbnail(for: frame.url, maxPixel: maxPixel, epoch: epoch) else {
            return
        }

        let cropped = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let pipeline = FramePipeline()
            guard let out = pipeline.cropOutputPreview(cg, crop: crop, outputSize: previewSize) else {
                return nil
            }
            return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
        }.value

        guard epoch == previewEpoch, let cropped else { return }
        compositionImage = cropped
    }

    @MainActor
    private func updateGradedPreview(viewSize: CGSize, epoch: UInt64) async {
        guard epoch == previewEpoch,
              let sequence = project.sequence,
              sequence.frames.indices.contains(project.playheadIndex)
        else {
            return
        }

        let frame = sequence.frames[project.playheadIndex]
        let playhead = project.playheadIndex
        let crop = project.crop
        let showOriginal = project.showOriginal
        let bakeOutput = project.previewOutputFull && !showOriginal
        let adjustments = showOriginal ? Adjustments.identity : project.adjustments
        // Cap bake resolution to the viewer — full 4K/8K isn't needed on screen.
        let outputSize = bakeOutput
            ? previewPixelSize(
                output: project.outputPixelSize,
                maxPixel: previewMaxPixel(for: viewSize, playing: false)
            )
            : project.outputPixelSize

        let image: NSImage? = await Task.detached(priority: .utility) {
            let input = FramePipelineInput(
                imageURL: frame.url,
                crop: crop,
                adjustments: adjustments,
                outputSize: outputSize,
                overlay: .none,
                overlayText: "",
                showOriginal: showOriginal,
                // Preview Full bakes crop/scale; burn-in stays in SwiftUI for correct opacity.
                compositionPreview: !showOriginal && !bakeOutput,
                exposureBias: 0
            )
            guard let cg = FramePipeline().renderCGImage(from: input) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value

        guard epoch == previewEpoch,
              playhead == project.playheadIndex,
              let image
        else { return }
        compositionImage = image
    }

    private func prefetchAroundPlayhead(sequence: ImageSequenceSpec, maxPixel: CGFloat) {
        let urls = frameURLs.isEmpty ? sequence.frames.map(\.url) : frameURLs
        if playback.isPlaying {
            frameCache.prefetch(
                urls: urls,
                around: project.playheadIndex,
                behind: 4,
                ahead: 48,
                maxPixelSize: maxPixel
            )
        } else {
            frameCache.prefetch(
                urls: urls,
                around: project.playheadIndex,
                behind: 12,
                ahead: 12,
                maxPixelSize: maxPixel
            )
        }
    }

    @MainActor
    private func loadThumbnail(for url: URL, maxPixel: CGFloat, epoch: UInt64) async -> NSImage? {
        if let cached = frameCache.cachedThumbnail(for: url, maxPixelSize: maxPixel) {
            return cached
        }
        let thumb = await frameCache.thumbnail(for: url, maxPixelSize: maxPixel)
        guard epoch == previewEpoch else { return nil }
        return thumb
    }

    /// While playing, decode smaller proxies so ImageIO can keep up with the playhead.
    private func previewMaxPixel(for viewSize: CGSize, playing: Bool) -> CGFloat {
        let viewLong = max(viewSize.width, viewSize.height)
        if playing {
            return min(1280, max(640, viewLong))
        }
        return min(2048, viewLong * 2)
    }

    /// Output aspect at (or below) viewer resolution for fast Preview Full frames.
    private func previewPixelSize(output: PixelSize, maxPixel: CGFloat) -> PixelSize {
        let w = CGFloat(output.width)
        let h = CGFloat(output.height)
        let longEdge = max(w, h)
        guard longEdge > 0 else { return PixelSize(width: 2, height: 2) }
        guard longEdge > maxPixel else { return output.even }
        let scale = maxPixel / longEdge
        return PixelSize(
            width: max(2, Int((w * scale).rounded())),
            height: max(2, Int((h * scale).rounded()))
        ).even
    }
}

/// Applies straighten rotation + cover scale only in composition preview mode.
private struct CompositionStraightenModifier: ViewModifier {
    var enabled: Bool
    var degrees: Double
    var coverScale: CGFloat
    var anchor: UnitPoint
    var clipSize: CGSize

    func body(content: Content) -> some View {
        if enabled {
            content
                .rotationEffect(.degrees(degrees), anchor: anchor)
                .scaleEffect(coverScale, anchor: anchor)
                .frame(width: clipSize.width, height: clipSize.height)
                .clipped()
        } else {
            content
        }
    }
}

struct EmptyStateView: View {
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Open an image sequence")
                    .font(.title2.weight(.semibold))
                Text("Drop a folder of numbered frames — img_0001.jpg, img_0002.jpg… — or choose Open.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: 360)
            }
            Button("Open Sequence…", action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
        }
        .padding(36)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.35))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 5]))
                .foregroundStyle(.white.opacity(0.18))
        }
        .frame(maxWidth: 460)
    }
}
