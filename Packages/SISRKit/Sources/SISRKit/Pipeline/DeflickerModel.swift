import Foundation

/// Luminance / color statistics for one metering region of a frame.
public struct DeflickerRegionStats: Equatable, Sendable {
    /// log2 linear luminance at `DeflickerFrameStats.quantileLevels`.
    public var quantiles: [Float]
    /// Mean log2(R/G) and log2(B/G) over well-exposed pixels.
    public var chromaRG: Float
    public var chromaBG: Float

    public init(quantiles: [Float], chromaRG: Float, chromaBG: Float) {
        self.quantiles = quantiles
        self.chromaRG = chromaRG
        self.chromaBG = chromaBG
    }
}

/// Everything the solver needs about one frame, measured on the graded, cropped output.
public struct DeflickerFrameStats: Equatable, Sendable {
    public static let quantileCount = 33
    /// Rank levels 1%…99%.
    public static let quantileLevels: [Double] = (0..<quantileCount).map {
        0.01 + 0.98 * Double($0) / Double(quantileCount - 1)
    }
    public static let gridColumns = 8
    public static let gridRows = 6

    /// Indexed by `DeflickerMetering.allCases` order.
    public var regions: [DeflickerRegionStats]
    /// log2 geometric-mean luminance per cell, row-major, top row first.
    public var grid: [Float]
    /// Camera exposure in stops: log2(t · ISO/100 / N²). nil when EXIF is missing.
    public var cameraExposure: Double?

    public init(regions: [DeflickerRegionStats], grid: [Float], cameraExposure: Double?) {
        self.regions = regions
        self.grid = grid
        self.cameraExposure = cameraExposure
    }

    public func region(_ metering: DeflickerMetering) -> DeflickerRegionStats {
        let index = DeflickerMetering.allCases.firstIndex(of: metering) ?? 0
        return regions[min(index, regions.count - 1)]
    }
}

/// Monotone tone remap expressed as log2 offsets at input luminance anchors.
public struct DeflickerToneCurve: Equatable, Sendable {
    /// Ascending log2 linear luminance anchors.
    public var anchors: [Float]
    /// Stops added at each anchor.
    public var offsets: [Float]

    public init(anchors: [Float], offsets: [Float]) {
        self.anchors = anchors
        self.offsets = offsets
    }

    public static let lutSize = 256

    /// sRGB-encoded 1D LUT (input i/255 → output), monotone and pinned at black / white.
    public func srgbLUT() -> [Float] {
        let n = Self.lutSize
        guard let firstAnchor = anchors.first, let lastAnchor = anchors.last else {
            return (0..<n).map { Float($0) / Float(n - 1) }
        }
        let firstV = DeflickerColor.linearToSRGB(exp2(firstAnchor))
        let lastV = DeflickerColor.linearToSRGB(exp2(lastAnchor))
        var lut = [Float](repeating: 0, count: n)
        var running: Float = 0
        for i in 0..<n {
            let v = Float(i) / Float(n - 1)
            let lin = DeflickerColor.srgbToLinear(v)
            let l = log2(max(lin, DeflickerColor.minLuminance))
            var offset: Float
            if l <= firstAnchor {
                offset = offsets[0] * (firstV > 0 ? min(1, v / firstV) : 0)
            } else if l >= lastAnchor {
                offset = offsets[offsets.count - 1] * (lastV < 1 ? max(0, (1 - v) / (1 - lastV)) : 0)
            } else {
                offset = Self.interpolate(l, anchors, offsets)
            }
            if v <= 0 { offset = 0 }
            let out = v <= 0 ? 0 : DeflickerColor.linearToSRGB(lin * exp2(offset))
            running = max(running, min(1, out))
            lut[i] = running
        }
        lut[n - 1] = max(lut[n - 1], 1)
        return lut
    }

    static func interpolate(_ x: Float, _ xs: [Float], _ ys: [Float]) -> Float {
        var lo = 0
        var hi = xs.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        let span = xs[hi] - xs[lo]
        guard span > 1e-6 else { return ys[lo] }
        let t = (x - xs[lo]) / span
        return ys[lo] + (ys[hi] - ys[lo]) * t
    }
}

/// Smooth per-region exposure offsets (stops), row-major, top row first.
public struct DeflickerGainGrid: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var stops: [Float]

    public init(columns: Int, rows: Int, stops: [Float]) {
        self.columns = columns
        self.rows = rows
        self.stops = stops
    }
}

/// Per-frame correction applied at the end of the grade, before any burn-in overlay.
public struct DeflickerCorrection: Equatable, Sendable {
    public var exposureEV: Double
    /// Linear channel multipliers (luminance-neutral).
    public var redGain: Double
    public var greenGain: Double
    public var blueGain: Double
    public var toneCurve: DeflickerToneCurve?
    public var localGrid: DeflickerGainGrid?

    public static let identity = DeflickerCorrection()

    public init(
        exposureEV: Double = 0,
        redGain: Double = 1,
        greenGain: Double = 1,
        blueGain: Double = 1,
        toneCurve: DeflickerToneCurve? = nil,
        localGrid: DeflickerGainGrid? = nil
    ) {
        self.exposureEV = exposureEV
        self.redGain = redGain
        self.greenGain = greenGain
        self.blueGain = blueGain
        self.toneCurve = toneCurve
        self.localGrid = localGrid
    }

    public var isIdentity: Bool { self == .identity }
}

/// Identifies what a measurement depends on so cached stats can be reused safely.
public struct DeflickerAnalysisKey: Equatable, Sendable {
    public var directoryPath: String
    public var frameCount: Int
    public var crop: CropState
    public var color: ColorAdjustments
    public var detail: DetailAdjustments
    public var outputSize: PixelSize

    public init(
        directoryPath: String,
        frameCount: Int,
        crop: CropState,
        color: ColorAdjustments,
        detail: DetailAdjustments,
        outputSize: PixelSize
    ) {
        self.directoryPath = directoryPath
        self.frameCount = frameCount
        self.crop = crop
        self.color = color
        self.detail = detail
        self.outputSize = outputSize
    }

    public init?(project: SequenceProjectSnapshot) {
        guard let sequence = project.sequence else { return nil }
        self.init(
            directoryPath: sequence.directory.path,
            frameCount: sequence.frameCount,
            crop: project.crop,
            color: project.adjustments.color,
            detail: project.adjustments.detail,
            outputSize: project.outputSize
        )
    }
}

/// Measured stats for a contiguous run of sequence frames.
public struct DeflickerAnalysis: Equatable, Sendable {
    public var key: DeflickerAnalysisKey
    /// Sequence index of `stats[0]`.
    public var startIndex: Int
    public var stats: [DeflickerFrameStats]

    public init(key: DeflickerAnalysisKey, startIndex: Int, stats: [DeflickerFrameStats]) {
        self.key = key
        self.startIndex = startIndex
        self.stats = stats
    }

    public var endIndex: Int { startIndex + stats.count - 1 }

    /// Stats for `range` when this analysis matches `key` and covers the range.
    public func stats(for range: TimelineRange, key other: DeflickerAnalysisKey) -> [DeflickerFrameStats]? {
        guard key == other, range.inIndex >= startIndex, range.outIndex <= endIndex else { return nil }
        return Array(stats[(range.inIndex - startIndex)...(range.outIndex - startIndex)])
    }
}

enum DeflickerColor {
    static let minLuminance: Float = 1.0 / 16384

    static func srgbToLinear(_ v: Float) -> Float {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func linearToSRGB(_ l: Float) -> Float {
        let c = max(0, l)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    static func luminance(r: Float, g: Float, b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
