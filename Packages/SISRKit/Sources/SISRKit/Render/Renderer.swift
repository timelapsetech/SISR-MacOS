import AppKit
import CoreGraphics
import CoreImage
import Foundation

public actor Renderer {
    private var cancelFlag = false

    public init() {}

    public func cancel() {
        cancelFlag = true
    }

    public func render(
        project: SequenceProjectSnapshot,
        progress: @Sendable @escaping (RenderProgress) -> Void
    ) async throws -> URL {
        cancelFlag = false

        guard let sequence = project.sequence else { throw RenderError.noSequence }
        let range = project.timeline.clamped(to: sequence.frameCount)
        let frames = Array(sequence.frames[range.inIndex...range.outIndex])
        guard !frames.isEmpty else { throw RenderError.noSequence }

        let outputSize = project.outputSize
        let settings = project.render
        guard var outputURL = OutputNaming.outputURL(
            settings: settings,
            cropLabel: settings.preset == .original ? nil : settings.preset.rawValue,
            outputSize: outputSize
        ) else {
            throw RenderError.invalidOutput
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let pipeline = FramePipeline()
        let start = Date()
        let total = frames.count

        func emit(
            done: Int,
            thumb: NSImage? = nil,
            finished: Bool = false,
            cancelled: Bool = false,
            error: String? = nil,
            status: String? = nil
        ) {
            let elapsed = Date().timeIntervalSince(start)
            let fps = elapsed > 0 ? Double(done) / elapsed : 0
            let remaining = done > 0 ? (elapsed / Double(done)) * Double(total - done) : nil
            var byteCount: Int64?
            if FileManager.default.fileExists(atPath: outputURL.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
               let size = attrs[.size] as? NSNumber
            {
                byteCount = size.int64Value
            }
            progress(RenderProgress(
                framesDone: done,
                framesTotal: total,
                framesPerSecond: fps,
                elapsed: elapsed,
                eta: remaining,
                outputByteCount: byteCount,
                latestThumbnail: thumb,
                isFinished: finished,
                isCancelled: cancelled,
                errorMessage: error,
                outputURL: finished ? outputURL : nil,
                statusMessage: status
            ))
        }

        emit(done: 0, status: "Preparing…")

        // Deflicker analysis (optional) — advance the same progress bar while measuring frames.
        var exposureBiases = Array(repeating: 0.0, count: total)
        if project.adjustments.deflicker.enabled {
            let analyzer = DeflickerAnalyzer()
            let urls = frames.map(\.url)
            let startedAt = start
            do {
                exposureBiases = try await analyzer.analyze(
                    urls: urls,
                    settings: project.adjustments.deflicker,
                    progress: { done, frameTotal in
                        let elapsed = Date().timeIntervalSince(startedAt)
                        let fps = elapsed > 0 ? Double(done) / elapsed : 0
                        let remaining = done > 0
                            ? (elapsed / Double(done)) * Double(frameTotal - done)
                            : nil
                        progress(RenderProgress(
                            framesDone: done,
                            framesTotal: frameTotal,
                            framesPerSecond: fps,
                            elapsed: elapsed,
                            eta: remaining,
                            statusMessage: "Analyzing deflicker…"
                        ))
                    },
                    isCancelled: { Task.isCancelled }
                )
            } catch RenderError.cancelled {
                emit(done: 0, cancelled: true)
                throw RenderError.cancelled
            }
            if cancelFlag || Task.isCancelled {
                emit(done: 0, cancelled: true)
                throw RenderError.cancelled
            }
            pipeline.clearCaches()
        }

        emit(done: 0, status: "Opening writer…")

        if settings.codec == .gif {
            let stream = try GIFWriter.Stream(
                url: outputURL,
                fps: settings.suggestedFPS,
                frameCount: total
            )
            outputURL = stream.resolvedURL
            do {
                for (i, frame) in frames.enumerated() {
                    if cancelFlag {
                        stream.cancel()
                        emit(done: i, cancelled: true)
                        throw RenderError.cancelled
                    }
                    try autoreleasepool {
                        let overlayText = makeOverlayText(
                            project: project,
                            renderIndex: i,
                            sourceFrame: frame,
                            total: total
                        )
                        let input = FramePipelineInput(
                            imageURL: frame.url,
                            crop: project.crop,
                            adjustments: project.adjustments,
                            outputSize: outputSize,
                            overlay: settings.overlay,
                            overlayText: overlayText,
                            overlayBackgroundOpacity: settings.overlayBackgroundOpacity,
                            showOriginal: false,
                            exposureBias: exposureBiases.indices.contains(i) ? exposureBiases[i] : 0
                        )
                        guard let cg = pipeline.renderCGImage(from: input) else {
                            throw RenderError.frameFailed(i)
                        }
                        stream.append(cg)

                        if i == 0 || i == total - 1 || i % 8 == 0 {
                            let thumb = progressThumbnail(pipeline: pipeline, cgImage: cg)
                            emit(done: i + 1, thumb: thumb)
                        } else {
                            emit(done: i + 1)
                        }
                    }
                    if i % 24 == 0 {
                        pipeline.clearCaches()
                    }
                    await Task.yield()
                }
                try stream.finish()
                pipeline.clearCaches()
                emit(done: total, finished: true)
                return outputURL
            } catch {
                stream.cancel()
                pipeline.clearCaches()
                throw error
            }
        }

        let writer = VideoWriter(
            outputURL: outputURL,
            size: outputSize,
            fps: settings.fps,
            codec: settings.codec,
            encode: settings.videoEncode
        )
        try writer.start()
        outputURL = writer.outputURL

        do {
            for (i, frame) in frames.enumerated() {
                if cancelFlag {
                    writer.cancel()
                    emit(done: i, cancelled: true)
                    throw RenderError.cancelled
                }
                try autoreleasepool {
                    let overlayText = makeOverlayText(
                        project: project,
                        renderIndex: i,
                        sourceFrame: frame,
                        total: total
                    )
                    let input = FramePipelineInput(
                        imageURL: frame.url,
                        crop: project.crop,
                        adjustments: project.adjustments,
                        outputSize: outputSize,
                        overlay: settings.overlay,
                        overlayText: overlayText,
                        overlayBackgroundOpacity: settings.overlayBackgroundOpacity,
                        showOriginal: false,
                        exposureBias: exposureBiases.indices.contains(i) ? exposureBiases[i] : 0
                    )
                    guard let ci = pipeline.makeImage(from: input) else {
                        writer.cancel()
                        throw RenderError.frameFailed(i)
                    }
                    try writer.append(ciImage: ci, context: pipeline.ciContext)

                    if i == 0 || i == total - 1 || i % 8 == 0 {
                        let thumb = progressThumbnail(pipeline: pipeline, ciImage: ci)
                        emit(done: i + 1, thumb: thumb)
                    } else {
                        emit(done: i + 1)
                    }
                }
                if i % 24 == 0 {
                    pipeline.clearCaches()
                }
                await Task.yield()
            }
            try await writer.finish()
            pipeline.clearCaches()
            emit(done: total, finished: true)
            return outputURL
        } catch {
            writer.cancel()
            pipeline.clearCaches()
            throw error
        }
    }

    private func progressThumbnail(pipeline: FramePipeline, ciImage: CIImage) -> NSImage? {
        guard let cg = pipeline.renderProgressThumbnail(from: ciImage, maxLongEdge: 240) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func progressThumbnail(pipeline: FramePipeline, cgImage: CGImage) -> NSImage? {
        guard let cg = pipeline.renderProgressThumbnail(from: cgImage, maxLongEdge: 240) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func makeOverlayText(
        project: SequenceProjectSnapshot,
        renderIndex: Int,
        sourceFrame: ImageSequenceFrame,
        total: Int
    ) -> String {
        switch project.render.overlay {
        case .none:
            return ""
        case .date:
            let raw = project.frameDates.indices.contains(project.timeline.inIndex + renderIndex)
                ? project.frameDates[project.timeline.inIndex + renderIndex]
                : MetadataReader.extractDateTime(from: sourceFrame.url)
            return DateOverlayFormatter.format(raw, parts: project.render.dateParts)
        case .frame:
            return OverlayRenderer.frameOverlayText(
                indexInRender: renderIndex,
                sourceFrameNumber: sourceFrame.frameNumber,
                mode: project.render.frameNumberMode,
                pad: project.sequence?.numberWidth ?? 4,
                totalFrames: total
            )
        }
    }
}

/// Sendable snapshot of project state for rendering off the main actor.
public struct SequenceProjectSnapshot: Sendable {
    public var sequence: ImageSequenceSpec?
    public var crop: CropState
    public var adjustments: Adjustments
    public var render: RenderSettings
    public var timeline: TimelineRange
    public var outputSize: PixelSize
    public var frameDates: [String]

    public init(
        sequence: ImageSequenceSpec?,
        crop: CropState,
        adjustments: Adjustments,
        render: RenderSettings,
        timeline: TimelineRange,
        outputSize: PixelSize,
        frameDates: [String] = []
    ) {
        self.sequence = sequence
        self.crop = crop
        self.adjustments = adjustments
        self.render = render
        self.timeline = timeline
        self.outputSize = outputSize
        self.frameDates = frameDates
    }

    public init(from project: SequenceProject) {
        self.init(
            sequence: project.sequence,
            crop: project.crop,
            adjustments: project.adjustments,
            render: project.render,
            timeline: project.timeline,
            outputSize: project.outputPixelSize,
            frameDates: project.frameDates
        )
    }
}
