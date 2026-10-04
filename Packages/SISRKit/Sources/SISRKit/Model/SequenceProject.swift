import CoreGraphics
import Foundation
import Observation

public struct TimelineRange: Codable, Equatable, Sendable {
    /// Inclusive start index into `sequence.frames`.
    public var inIndex: Int
    /// Inclusive end index into `sequence.frames`.
    public var outIndex: Int

    public init(inIndex: Int = 0, outIndex: Int = 0) {
        self.inIndex = max(0, inIndex)
        self.outIndex = max(self.inIndex, outIndex)
    }

    public var frameCount: Int {
        outIndex - inIndex + 1
    }

    public func clamped(to frameCount: Int) -> TimelineRange {
        guard frameCount > 0 else { return TimelineRange(inIndex: 0, outIndex: 0) }
        let last = frameCount - 1
        let i = min(max(0, inIndex), last)
        let o = min(max(i, outIndex), last)
        return TimelineRange(inIndex: i, outIndex: o)
    }
}

/// Persisted / transferable project state for one image sequence.
public struct SequenceProjectState: Codable, Equatable, Sendable {
    public var crop: CropState
    public var adjustments: Adjustments
    public var render: RenderSettings
    public var timeline: TimelineRange
    public var playheadIndex: Int
    public var sourceBookmark: Data?
    public var sourcePath: String?

    public init(
        crop: CropState = .fullFrame,
        adjustments: Adjustments = .identity,
        render: RenderSettings = .default,
        timeline: TimelineRange = TimelineRange(),
        playheadIndex: Int = 0,
        sourceBookmark: Data? = nil,
        sourcePath: String? = nil
    ) {
        self.crop = crop
        self.adjustments = adjustments
        self.render = render
        self.timeline = timeline
        self.playheadIndex = playheadIndex
        self.sourceBookmark = sourceBookmark
        self.sourcePath = sourcePath
    }
}

@Observable
public final class SequenceProject {
    public var sequence: ImageSequenceSpec?
    public var sourceSize: CGSize = .zero
    public var crop: CropState = .fullFrame
    public var adjustments: Adjustments = .identity
    public var render: RenderSettings = .default
    public var timeline: TimelineRange = TimelineRange()
    public var playheadIndex: Int = 0
    public var showOriginal: Bool = false
    /// Session-only: fit the cropped/output frame as large as possible in the viewer.
    public var previewOutputFull: Bool = false
    public var sourceBookmark: Data?
    public var loadError: String?
    public var frameDates: [String] = []

    public init() {}

    public var hasSequence: Bool { sequence != nil }

    public var frameCount: Int { sequence?.frameCount ?? 0 }

    public var displayTitle: String {
        sequence?.displayName ?? "SISR"
    }

    public var subtitle: String {
        guard let sequence, sourceSize.width > 0 else { return "Open an image sequence" }
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        let frames = nf.string(from: NSNumber(value: sequence.frameCount)) ?? "\(sequence.frameCount)"
        return "\(frames) frames · \(Int(sourceSize.width))×\(Int(sourceSize.height))"
    }

    /// Pixel size of the source after flip/90° orientation (matches the render pipeline).
    public var orientedSourceSize: CGSize {
        crop.orientedSize(of: sourceSize)
    }

    public var cropPixelSize: PixelSize {
        crop.pixelSize(sourceSize: orientedSourceSize)
    }

    public var outputPixelSize: PixelSize {
        render.outputPixelSize(cropSize: cropPixelSize)
    }

    public var selectedFrameCount: Int {
        timeline.clamped(to: frameCount).frameCount
    }

    public var durationSeconds: Double {
        let fps = render.codec == .gif ? max(0.01, render.suggestedFPS) : max(0.01, render.fps)
        return Double(selectedFrameCount) / fps
    }

    public var resolutionChecks: [ResolutionCheck] {
        let cropSize = cropPixelSize
        guard cropSize.width > 0 else { return [] }
        let aspect = cropSize.aspect
        return OutputPreset.matchingAspect(aspect).compactMap {
            ResolutionCheck.evaluate(crop: cropSize, preset: $0)
        }.sorted { $0.target.width > $1.target.width }
    }

    /// Fitness for the currently chosen output size (including Custom / Original).
    public var currentOutputResolutionCheck: ResolutionCheck? {
        let cropSize = cropPixelSize
        let output = outputPixelSize
        guard cropSize.width > 0, output.width > 0 else { return nil }
        return ResolutionCheck.evaluate(crop: cropSize, target: output, preset: render.preset)
    }

    public var willUpscaleOnRender: Bool {
        currentOutputResolutionCheck?.willUpscale ?? false
    }

    /// Clears the loaded sequence and returns to the empty state (keeps encode defaults).
    public func close() {
        sequence = nil
        sourceSize = .zero
        sourceBookmark = nil
        frameDates = []
        playheadIndex = 0
        timeline = TimelineRange()
        showOriginal = false
        previewOutputFull = false
        loadError = nil
        crop = .fullFrame
        // Keep adjustments / render prefs so the next open feels continuous.
    }

    public func load(directory: URL, bookmark: Data? = nil) throws {
        loadError = nil
        let spec = try SequenceScanner.scanDirectory(directory)
        sequence = spec
        sourceBookmark = bookmark
        render.outputBaseName = spec.displayName
        // Never default the render destination to the sequence folder — user must pick one.
        clearOutputIfPointsAtSource()
        timeline = TimelineRange(inIndex: 0, outIndex: max(0, spec.frameCount - 1))
        playheadIndex = 0

        if let first = spec.frames.first,
           let size = MetadataReader.imagePixelSize(of: first.url)
        {
            sourceSize = size
        } else {
            sourceSize = .zero
        }

        crop = .fullFrame
        if let lock = render.preset.aspectLock {
            crop.setAspectLock(lock, sourceSize: sourceSize)
        } else {
            crop.setAspectLock(.matchSource, sourceSize: sourceSize)
        }

        frameDates = spec.frames.map { MetadataReader.extractDateTime(from: $0.url) }
    }

    public func applyPreset(_ preset: OutputPreset) {
        render.preset = preset
        switch preset {
        case .original:
            // Full-frame source pixels in / out — no crop box.
            resetCropToFullFrame()
        case .fitWithin:
            resetCropToFullFrame()
            // Leave max width/height as the user set them (one, both, or neither).
            // Neither ⇒ output stays at full-frame pixels until a limit is entered.
        default:
            if let lock = preset.aspectLock, GeometryUtil.isValidSize(sourceSize) {
                crop.setAspectLock(lock, sourceSize: sourceSize)
            }
        }
    }

    /// Output at the source (or current full-frame) pixel size with no crop.
    public func applyNativeFullFrameOutput() {
        applyPreset(.original)
    }

    /// Full frame, scaled down to fit within max width and/or height (aspect preserved, no crop).
    public func applyScaledFullFrame(maxWidth: Int? = nil, maxHeight: Int? = nil) {
        render.maxWidth = maxWidth.flatMap { $0 > 0 ? $0 : nil }
        render.maxHeight = maxHeight.flatMap { $0 > 0 ? $0 : nil }
        applyPreset(.fitWithin)
    }

    /// Restore a full-frame crop locked to the source aspect (clears straighten / flips).
    public func resetCropToFullFrame() {
        crop = .fullFrame
        if GeometryUtil.isValidSize(sourceSize) {
            crop.setAspectLock(.matchSource, sourceSize: sourceSize)
        }
    }

    public func setInPoint() {
        let clamped = min(max(0, playheadIndex), max(0, frameCount - 1))
        timeline.inIndex = clamped
        if timeline.outIndex < clamped {
            timeline.outIndex = clamped
        }
    }

    public func setOutPoint() {
        let clamped = min(max(0, playheadIndex), max(0, frameCount - 1))
        timeline.outIndex = clamped
        if timeline.inIndex > clamped {
            timeline.inIndex = clamped
        }
    }

    public func clearInOut() {
        timeline = TimelineRange(inIndex: 0, outIndex: max(0, frameCount - 1))
    }

    public func dateString(at index: Int) -> String? {
        guard frameDates.indices.contains(index) else { return nil }
        return frameDates[index]
    }

    public func formattedOverlayDate(at index: Int) -> String {
        guard let raw = dateString(at: index) else { return "" }
        return DateOverlayFormatter.format(raw, parts: render.dateParts)
    }

    /// Burn-in text for the current playhead (viewer / preview-full bake).
    public func previewOverlayText(at index: Int) -> String {
        switch render.overlay {
        case .none:
            return ""
        case .date:
            let formatted = formattedOverlayDate(at: index)
            if !formatted.isEmpty { return formatted }
            return DateOverlayFormatter.format("2024:01:05 13:30:00", parts: render.dateParts)
        case .frame:
            guard let sequence,
                  sequence.frames.indices.contains(index)
            else {
                return "FRAME 0001"
            }
            let frame = sequence.frames[index]
            let indexInRender = max(0, index - timeline.inIndex)
            let total = max(1, selectedFrameCount)
            return OverlayRenderer.frameOverlayText(
                indexInRender: indexInRender,
                sourceFrameNumber: frame.frameNumber,
                mode: render.frameNumberMode,
                pad: sequence.numberWidth,
                totalFrames: total
            )
        }
    }

    public var persistedState: SequenceProjectState {
        SequenceProjectState(
            crop: crop,
            adjustments: adjustments,
            render: render,
            timeline: timeline,
            playheadIndex: playheadIndex,
            sourceBookmark: sourceBookmark,
            sourcePath: sequence?.directory.path
        )
    }

    public func restore(_ state: SequenceProjectState) {
        crop = state.crop
        adjustments = state.adjustments
        render = state.render
        timeline = state.timeline.clamped(to: frameCount)
        playheadIndex = min(max(0, state.playheadIndex), max(0, frameCount - 1))
        if let bookmark = state.sourceBookmark {
            sourceBookmark = bookmark
        }
        // Drop legacy autosaves that pointed output at the sequence folder.
        clearOutputIfPointsAtSource()
    }

    /// True when a destination folder is set (path non-empty).
    public var hasOutputDirectory: Bool {
        guard let path = render.outputDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else { return false }
        return true
    }

    /// Clears output when it matches the loaded sequence directory.
    public func clearOutputIfPointsAtSource() {
        guard let source = sequence?.directory.path,
              let out = render.outputDirectoryPath,
              out == source
        else { return }
        render.outputDirectoryPath = nil
        render.outputDirectoryBookmark = nil
    }
}
