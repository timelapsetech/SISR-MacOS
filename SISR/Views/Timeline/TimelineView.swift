import SwiftUI
import SISRKit

struct TimelineView: View {
    @Bindable var project: SequenceProject
    var frameCache: FrameCache
    var playback: PlaybackController

    /// 1 = fit entire sequence in the viewport; higher values zoom in (scrollable).
    @State private var timelineZoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    playback.toggle(project: project)
                } label: {
                    Image(systemName: playback.isPlaying && !playback.isPlayingInOut
                          ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!project.hasSequence)
                .help(
                    playback.isPlaying && !playback.isPlayingInOut
                        ? "Pause (K / Space)"
                        : "Play full sequence from playhead (Space)"
                )

                Button {
                    playback.toggleInOut(project: project)
                } label: {
                    Image(systemName: playback.isPlaying && playback.isPlayingInOut
                          ? "pause.fill" : "play.square.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!project.hasSequence)
                .help(
                    playback.isPlaying && playback.isPlayingInOut
                        ? "Pause In→Out"
                        : "Play In to Out (⇧Space)"
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(frameLabel)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                    if let date = project.dateString(at: project.playheadIndex) {
                        Text(DateOverlayFormatter.format(date, parts: project.render.dateParts))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    MetricPill(
                        text: "In \(project.timeline.inIndex + 1)",
                        tone: Color.accentColor
                    )
                    MetricPill(
                        text: "Out \(project.timeline.outIndex + 1)",
                        tone: Color.accentColor
                    )
                }

                ControlGroup {
                    Button {
                        playback.goToStart(project: project)
                    } label: {
                        Image(systemName: "arrow.left.to.line.compact")
                    }
                    .help("Go to Start of Sequence (Home)")
                    .disabled(!project.hasSequence)

                    Button {
                        playback.goToIn(project: project)
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .help("Go to In Point (⇧I)")
                    .disabled(!project.hasSequence)

                    Button("I") { project.setInPoint() }
                        .help("Set In (I)")

                    Button("O") { project.setOutPoint() }
                        .help("Set Out (O)")

                    Button {
                        playback.goToOut(project: project)
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .help("Go to Out Point (⇧O)")
                    .disabled(!project.hasSequence)

                    Button {
                        playback.goToEnd(project: project)
                    } label: {
                        Image(systemName: "arrow.right.to.line.compact")
                    }
                    .help("Go to End of Sequence (End)")
                    .disabled(!project.hasSequence)
                }
                .controlSize(.small)

                ControlGroup {
                    Button {
                        adjustZoom(factor: 1 / 1.35)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom timeline out")
                    .disabled(!project.hasSequence || timelineZoom <= 1.001)

                    Button("Fit") {
                        timelineZoom = 1
                    }
                    .help("Show whole sequence")
                    .disabled(!project.hasSequence || timelineZoom <= 1.001)

                    Button {
                        adjustZoom(factor: 1.35)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom timeline in")
                    .disabled(!project.hasSequence)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            FilmstripView(
                project: project,
                frameCache: frameCache,
                playback: playback,
                zoom: $timelineZoom
            )
            .frame(height: 76)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.filmstripTrack)
        .overlay(alignment: .top) {
            SoftDivider()
        }
        .onChange(of: project.sequence?.directory.path) { _, _ in
            timelineZoom = 1
        }
    }

    private var frameLabel: String {
        guard project.frameCount > 0 else { return "— / —" }
        let fps = max(0.01, project.render.fps)
        let t = Double(project.playheadIndex) / fps
        let tc = formatTimecode(t)
        return "\(project.playheadIndex + 1)/\(project.frameCount)  \(tc)"
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let f = Int((seconds - Double(total)) * project.render.fps)
        if h > 0 {
            return String(format: "%02d:%02d:%02d:%02d", h, m, s, f)
        }
        return String(format: "%02d:%02d:%02d", m, s, f)
    }

    private func adjustZoom(factor: CGFloat) {
        timelineZoom = max(1, timelineZoom * factor)
    }
}

/// One filmstrip tile covering a contiguous span of source frames.
private struct FilmstripSample: Identifiable, Equatable {
    let id: Int
    /// Representative frame shown in the tile.
    let frameIndex: Int
    /// Inclusive start / exclusive end into the sequence.
    let start: Int
    let end: Int

    func contains(_ playhead: Int) -> Bool {
        playhead >= start && playhead < end
    }
}

struct FilmstripView: View {
    @Bindable var project: SequenceProject
    var frameCache: FrameCache
    var playback: PlaybackController
    @Binding var zoom: CGFloat

    @State private var pinchBase: CGFloat = 1
    @State private var lastScrolledSampleID: Int?

    private let maxThumbWidth: CGFloat = 80
    /// When zoomed out, don't draw thumbs narrower than this — sample instead.
    private let minSampleThumbWidth: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let count = max(1, project.frameCount)
            let maxZoom = Self.maxZoom(
                viewportWidth: geo.size.width,
                frameCount: count,
                maxThumbWidth: maxThumbWidth
            )
            let clampedZoom = GeometryUtil.clamp(zoom, min: 1, max: maxZoom)
            let contentWidth = max(geo.size.width, geo.size.width * clampedZoom)
            let unitWidth = contentWidth / CGFloat(count)
            let samples = Self.makeSamples(
                frameCount: project.frameCount,
                contentWidth: contentWidth,
                minThumbWidth: minSampleThumbWidth
            )

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: clampedZoom > 1.02) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                            .frame(width: contentWidth, height: geo.size.height)

                        if project.frameCount > 0 {
                            let range = project.timeline.clamped(to: project.frameCount)
                            let x0 = CGFloat(range.inIndex) * unitWidth
                            let bandW = CGFloat(range.outIndex - range.inIndex + 1) * unitWidth
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: max(2, bandW), height: geo.size.height)
                                .offset(x: x0)
                        }

                        LazyHStack(spacing: 0) {
                            ForEach(samples) { sample in
                                let width = max(
                                    1,
                                    contentWidth * CGFloat(sample.end - sample.start) / CGFloat(count)
                                )
                                FilmstripCell(
                                    url: project.sequence?.frames[sample.frameIndex].url,
                                    selected: sample.contains(project.playheadIndex),
                                    inRange: sample.frameIndex >= project.timeline.inIndex
                                        && sample.frameIndex <= project.timeline.outIndex,
                                    frameCache: frameCache,
                                    width: width,
                                    height: geo.size.height
                                )
                                .id(sample.id)
                            }
                        }
                        .frame(width: contentWidth, height: geo.size.height, alignment: .leading)

                        if project.frameCount > 0 {
                            let x = (CGFloat(project.playheadIndex) + 0.5) * unitWidth
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 2, height: geo.size.height - 4)
                                .position(x: x, y: geo.size.height / 2)
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 0)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: contentWidth, height: geo.size.height)
                    .coordinateSpace(name: "filmstrip")
                    .contentShape(Rectangle())
                    // Simultaneous so trackpad scroll still pans when zoomed in.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("filmstrip"))
                            .onChanged { value in
                                seek(at: value.location.x, contentWidth: contentWidth)
                            }
                    )
                }
                .scrollDisabled(clampedZoom <= 1.02)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let next = pinchBase * value.magnification
                            zoom = GeometryUtil.clamp(next, min: 1, max: maxZoom)
                        }
                        .onEnded { _ in
                            pinchBase = GeometryUtil.clamp(zoom, min: 1, max: maxZoom)
                        }
                )
                .onChange(of: zoom) { _, _ in
                    pinchBase = GeometryUtil.clamp(zoom, min: 1, max: maxZoom)
                    if zoom > maxZoom {
                        zoom = maxZoom
                    }
                    scrollToPlayhead(proxy: proxy, samples: samples, animated: false)
                }
                .onChange(of: project.playheadIndex) { _, index in
                    // During play: only scroll when the sampled tile changes; skip filmstrip
                    // prefetch so ImageIO stays focused on viewer frames.
                    let sampleID = samples.first(where: { $0.contains(index) })?.id
                    if clampedZoom > 1.02, sampleID != lastScrolledSampleID {
                        scrollToPlayhead(proxy: proxy, samples: samples, animated: false)
                    }
                    if !playback.isPlaying {
                        prefetch(samples: samples, playhead: index)
                    }
                }
                .onChange(of: maxZoom) { _, newMax in
                    if zoom > newMax {
                        zoom = newMax
                    }
                }
                .onChange(of: samples) { _, newSamples in
                    guard !playback.isPlaying else { return }
                    prefetch(samples: newSamples, playhead: project.playheadIndex)
                }
                .onChange(of: playback.isPlaying) { _, playing in
                    if !playing {
                        prefetch(samples: samples, playhead: project.playheadIndex)
                    }
                }
                .onAppear {
                    pinchBase = clampedZoom
                    prefetch(samples: samples, playhead: project.playheadIndex)
                    scrollToPlayhead(proxy: proxy, samples: samples, animated: false)
                }
            }
        }
    }

    private func seek(at x: CGFloat, contentWidth: CGFloat) {
        guard project.frameCount > 0, contentWidth > 0 else { return }
        let t = GeometryUtil.clamp(x / contentWidth, min: 0, max: 0.999_999)
        project.playheadIndex = min(
            project.frameCount - 1,
            Int(t * CGFloat(project.frameCount))
        )
    }

    private func scrollToPlayhead(
        proxy: ScrollViewProxy,
        samples: [FilmstripSample],
        animated: Bool
    ) {
        guard let sample = samples.first(where: { $0.contains(project.playheadIndex) })
                ?? samples.last
        else { return }
        lastScrolledSampleID = sample.id
        if animated {
            withAnimation(.linear(duration: 0.08)) {
                proxy.scrollTo(sample.id, anchor: .center)
            }
        } else {
            proxy.scrollTo(sample.id, anchor: .center)
        }
    }

    private func prefetch(samples: [FilmstripSample], playhead: Int) {
        guard let frames = project.sequence?.frames, !samples.isEmpty else { return }
        let cover = samples.first(where: { $0.contains(playhead) }) ?? samples[samples.count / 2]
        let center = cover.id
        let window = 12
        let lo = max(0, center - window)
        let hi = min(samples.count, center + window + 1)
        var urls = samples[lo..<hi].compactMap { sample -> URL? in
            guard frames.indices.contains(sample.frameIndex) else { return nil }
            return frames[sample.frameIndex].url
        }
        if frames.indices.contains(playhead) {
            urls.insert(frames[playhead].url, at: 0)
        }
        frameCache.prefetch(
            urls: urls,
            around: 0,
            behind: 0,
            ahead: max(0, urls.count - 1),
            maxPixelSize: 120
        )
    }

    /// Contiguous sample buckets so each tile stays ≥ `minThumbWidth` when zoomed out.
    fileprivate static func makeSamples(
        frameCount: Int,
        contentWidth: CGFloat,
        minThumbWidth: CGFloat
    ) -> [FilmstripSample] {
        guard frameCount > 0 else { return [] }
        let maxSamples = max(1, Int(floor(contentWidth / max(minThumbWidth, 1))))
        let stride = max(1, Int(ceil(Double(frameCount) / Double(maxSamples))))
        var samples: [FilmstripSample] = []
        var start = 0
        var id = 0
        while start < frameCount {
            let end = min(start + stride, frameCount)
            samples.append(
                FilmstripSample(
                    id: id,
                    frameIndex: start,
                    start: start,
                    end: end
                )
            )
            id += 1
            start = end
        }
        return samples
    }

    static func maxZoom(viewportWidth: CGFloat, frameCount: Int, maxThumbWidth: CGFloat) -> CGFloat {
        guard frameCount > 0, viewportWidth > 0 else { return 1 }
        let fitThumb = viewportWidth / CGFloat(frameCount)
        return max(1, maxThumbWidth / max(fitThumb, 0.0001))
    }
}

struct FilmstripCell: View {
    var url: URL?
    var selected: Bool
    var inRange: Bool
    var frameCache: FrameCache
    var width: CGFloat
    var height: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .opacity(inRange ? 1 : 0.35)
        .overlay {
            if selected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .task(id: url?.path) {
            guard let url else { return }
            if let cached = frameCache.cachedThumbnail(for: url, maxPixelSize: 120) {
                image = cached
                return
            }
            image = await frameCache.thumbnail(for: url, maxPixelSize: 120)
        }
    }
}
