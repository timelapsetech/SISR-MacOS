import Foundation

/// Corrections for a range plus curves for the brightness chart (stops, relative to the range median).
public struct DeflickerSolution: Equatable, Sendable {
    public var corrections: [DeflickerCorrection]
    public var measured: [Double]
    public var target: [Double]
    public var corrected: [Double]

    public static let empty = DeflickerSolution(corrections: [], measured: [], target: [], corrected: [])

    public init(corrections: [DeflickerCorrection], measured: [Double], target: [Double], corrected: [Double]) {
        self.corrections = corrections
        self.measured = measured
        self.target = target
        self.corrected = corrected
    }

    public var maxAbsExposure: Double {
        corrections.map { abs($0.exposureEV) }.max() ?? 0
    }

    /// RMS frame-to-frame brightness change before / after correction, in stops.
    public var measuredFlicker: Double { Self.flicker(measured) }
    public var correctedFlicker: Double { Self.flicker(corrected) }

    static func flicker(_ series: [Double]) -> Double {
        guard series.count > 1 else { return 0 }
        let sum = zip(series.dropFirst(), series).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        return (sum / Double(series.count - 1)).squareRoot()
    }
}

/// Turns measured frame stats into per-frame corrections. Pure and deterministic.
///
/// Model (all in log2 linear light, i.e. stops):
/// - Brightness `b` = trimmed mean of luminance quantiles (10–90%), robust to clipped skies.
/// - Target `T` = temporal smoothing of `b` (or a constant when locked); exposure = T − b.
/// - Contrast: each quantile's offset from `b` is smoothed over time the same way
///   (scale-time equalization, Delon 2006) and the difference becomes a tone curve.
/// - Color: log chroma (R/G, B/G) is smoothed and the difference becomes channel gains.
/// - Local: per-cell offsets from the frame mean are smoothed into a gain grid.
public enum DeflickerSolver {
    private static let maxChromaStops = 0.5
    private static let maxToneStops = 1.0
    private static let maxLocalStops = 1.5

    private static let trimmedLevelIndices: [Int] = DeflickerFrameStats.quantileLevels.indices.filter {
        let p = DeflickerFrameStats.quantileLevels[$0]
        return p >= 0.1 - 1e-9 && p <= 0.9 + 1e-9
    }

    /// `referenceIndex` is relative to `stats` (used only for a locked target).
    public static func solve(
        stats: [DeflickerFrameStats],
        settings: DeflickerSettings,
        referenceIndex: Int? = nil
    ) -> DeflickerSolution {
        let n = stats.count
        guard n > 0 else { return .empty }
        let strength = min(1, max(0, settings.strength))
        let maxEV = settings.maxCorrectionEV
        let reference = referenceIndex.flatMap { (0..<n).contains($0) ? $0 : nil }

        func temporalTarget(_ series: [Double]) -> [Double] {
            switch settings.target {
            case .followScene:
                return smooth(series, window: settings.windowSize, kind: settings.smoothing)
            case .locked:
                let value = reference.map { series[$0] } ?? median(series)
                return Array(repeating: value, count: n)
            }
        }

        let regions = stats.map { $0.region(settings.metering) }
        let quantiles: [[Double]] = regions.map { $0.quantiles.map { min(0, Double($0)) } }
        let brightness = quantiles.map(Self.brightness)

        var stepFree = brightness
        if settings.useCameraExposure, let exposure = filledCameraExposure(stats) {
            let ramp = smooth(exposure, window: max(settings.windowSize * 2 + 1, 25), kind: .gaussian)
            for i in 0..<n {
                stepFree[i] -= exposure[i] - ramp[i]
            }
        }
        let target = temporalTarget(stepFree)

        var exposures = [Double](repeating: 0, count: n)
        var predicted = brightness
        for i in 0..<n {
            let desired = brightness[i] + strength * (target[i] - brightness[i])
            var ev = clamp(desired - brightness[i], maxEV)
            // Simulated refinement passes: pixels pushed past white stop contributing,
            // so re-measure the shifted quantiles and nudge until the target is met.
            for _ in 0..<4 {
                let reached = Self.brightness(quantiles[i].map { min(0, $0 + ev) })
                let error = desired - reached
                if abs(error) < 0.005 { break }
                ev = clamp(ev + error, maxEV)
            }
            exposures[i] = ev
            predicted[i] = Self.brightness(quantiles[i].map { min(0, $0 + ev) })
        }

        var corrections = exposures.map { DeflickerCorrection(exposureEV: $0) }

        if settings.balanceColor {
            let rg = regions.map { Double($0.chromaRG) }
            let bg = regions.map { Double($0.chromaBG) }
            let targetRG = temporalTarget(rg)
            let targetBG = temporalTarget(bg)
            for i in 0..<n {
                let red = exp2(clamp(strength * (targetRG[i] - rg[i]), maxChromaStops))
                let blue = exp2(clamp(strength * (targetBG[i] - bg[i]), maxChromaStops))
                let norm = 1 / Double(DeflickerColor.luminance(r: Float(red), g: 1, b: Float(blue)))
                corrections[i].redGain = red * norm
                corrections[i].greenGain = norm
                corrections[i].blueGain = blue * norm
            }
        }

        if settings.matchContrast {
            let levels = DeflickerFrameStats.quantileCount
            var shapeTargets = [[Double]](repeating: [], count: levels)
            for p in 0..<levels {
                shapeTargets[p] = temporalTarget((0..<n).map { quantiles[$0][p] - brightness[$0] })
            }
            for i in 0..<n {
                let deltas = (0..<levels).map { p in
                    strength * (shapeTargets[p][i] - (quantiles[i][p] - brightness[i]))
                }
                corrections[i].toneCurve = toneCurve(
                    quantiles: quantiles[i],
                    exposure: exposures[i],
                    deltas: deltas
                )
            }
        }

        if let dims = settings.localGrid.dimensions {
            let cells = stats.map { resampleGrid($0.grid, columns: dims.columns, rows: dims.rows) }
            let residuals = cells.map { grid -> [Double] in
                let mean = grid.reduce(0, +) / Double(max(1, grid.count))
                return grid.map { $0 - mean }
            }
            let cellCount = dims.columns * dims.rows
            var cellTargets = [[Double]](repeating: [], count: cellCount)
            for c in 0..<cellCount {
                cellTargets[c] = temporalTarget(residuals.map { $0[c] })
            }
            for i in 0..<n {
                var stops = (0..<cellCount).map { c in strength * (cellTargets[c][i] - residuals[i][c]) }
                let mean = stops.reduce(0, +) / Double(cellCount)
                stops = stops.map { $0 - mean }
                stops = blurGrid(stops, columns: dims.columns, rows: dims.rows)
                    .map { clamp($0, maxLocalStops) }
                guard stops.contains(where: { abs($0) >= 0.02 }) else { continue }
                corrections[i].localGrid = DeflickerGainGrid(
                    columns: dims.columns,
                    rows: dims.rows,
                    stops: stops.map(Float.init)
                )
            }
        }

        let center = median(brightness)
        return DeflickerSolution(
            corrections: corrections,
            measured: brightness.map { $0 - center },
            target: target.map { $0 - center },
            corrected: predicted.map { $0 - center }
        )
    }

    // MARK: - Measures

    static func brightness(_ quantiles: [Double]) -> Double {
        let idx = trimmedLevelIndices
        guard !idx.isEmpty, quantiles.count == DeflickerFrameStats.quantileCount else {
            return quantiles.isEmpty ? 0 : quantiles.reduce(0, +) / Double(quantiles.count)
        }
        return idx.reduce(0) { $0 + quantiles[$1] } / Double(idx.count)
    }

    /// EXIF exposure with gaps filled from the nearest frame; nil when mostly missing.
    static func filledCameraExposure(_ stats: [DeflickerFrameStats]) -> [Double]? {
        let raw = stats.map(\.cameraExposure)
        let known = raw.compactMap { $0 }
        guard !known.isEmpty, known.count * 2 >= raw.count else { return nil }
        var filled = [Double](repeating: known[0], count: raw.count)
        var last = known[0]
        for (i, value) in raw.enumerated() {
            if let value { last = value }
            filled[i] = last
        }
        return filled
    }

    // MARK: - Tone curve

    private static func toneCurve(quantiles: [Double], exposure: Double, deltas raw: [Double]) -> DeflickerToneCurve? {
        let idx = trimmedLevelIndices
        let mean = idx.reduce(0) { $0 + raw[$1] } / Double(max(1, idx.count))
        var anchors: [Float] = []
        var offsets: [Float] = []
        for p in 0..<quantiles.count {
            let anchor = min(0, quantiles[p] + exposure)
            // Clipped highlights carry no tonal information.
            let offset = anchor > -0.02 ? 0 : clamp(raw[p] - mean, maxToneStops)
            if let last = anchors.last, Float(anchor) <= last + 1e-3 { continue }
            anchors.append(Float(anchor))
            offsets.append(Float(offset))
        }
        guard anchors.count >= 2, offsets.contains(where: { abs($0) >= 0.01 }) else { return nil }
        return DeflickerToneCurve(anchors: anchors, offsets: offsets)
    }

    // MARK: - Grid helpers

    static func resampleGrid(_ grid: [Float], columns: Int, rows: Int) -> [Double] {
        let srcC = DeflickerFrameStats.gridColumns
        let srcR = DeflickerFrameStats.gridRows
        guard grid.count == srcC * srcR else { return [Double](repeating: 0, count: columns * rows) }
        var out = [Double](repeating: 0, count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let r0 = r * srcR / rows
                let r1 = max(r0 + 1, (r + 1) * srcR / rows)
                let c0 = c * srcC / columns
                let c1 = max(c0 + 1, (c + 1) * srcC / columns)
                var sum = 0.0
                for sr in r0..<r1 {
                    for sc in c0..<c1 {
                        sum += Double(grid[sr * srcC + sc])
                    }
                }
                out[r * columns + c] = sum / Double((r1 - r0) * (c1 - c0))
            }
        }
        return out
    }

    /// 1-2-1 separable blur with edge clamping, so neighboring cells blend smoothly.
    static func blurGrid(_ values: [Double], columns: Int, rows: Int) -> [Double] {
        func at(_ v: [Double], _ r: Int, _ c: Int) -> Double {
            v[min(rows - 1, max(0, r)) * columns + min(columns - 1, max(0, c))]
        }
        var horizontal = values
        for r in 0..<rows {
            for c in 0..<columns {
                horizontal[r * columns + c] = (at(values, r, c - 1) + 2 * at(values, r, c) + at(values, r, c + 1)) / 4
            }
        }
        var out = horizontal
        for r in 0..<rows {
            for c in 0..<columns {
                out[r * columns + c] = (at(horizontal, r - 1, c) + 2 * at(horizontal, r, c) + at(horizontal, r + 1, c)) / 4
            }
        }
        return out
    }

    // MARK: - Temporal filters

    /// Smooths `series` over `window` frames. Ends are padded with a least-squares line through
    /// the nearest window of frames so sunrise / sunset trends continue instead of flattening.
    public static func smooth(_ series: [Double], window: Int, kind: DeflickerSmoothing) -> [Double] {
        let n = series.count
        guard n > 1 else { return series }
        let size = DeflickerSettings.normalizedWindow(window)
        let half = max(1, size / 2)
        let padded = trendPadded(series, pad: half, fitLength: size)
        let filtered: [Double]
        switch kind {
        case .average:
            filtered = boxFilter(padded, half: half)
        case .gaussian:
            filtered = gaussianFilter(padded, half: half, sigma: Double(half) / 2)
        case .robust:
            // A median flips between modes when sun and cloud frames alternate, so use a
            // trimmed mean: outliers are discarded, two-level alternation still averages out.
            let trimmed = trimmedMeanFilter(padded, half: half, trim: 0.25)
            let h = max(1, half / 2)
            filtered = gaussianFilter(trimmed, half: h, sigma: Double(h) / 2)
        }
        return Array(filtered[half..<(half + n)])
    }

    static func trendPadded(_ x: [Double], pad: Int, fitLength: Int) -> [Double] {
        let n = x.count
        let k = max(2, min(n, fitLength))
        let left = lineFit(Array(x[0..<k]))
        let right = lineFit(Array(x[(n - k)..<n]))
        var out = [Double]()
        out.reserveCapacity(n + 2 * pad)
        for j in stride(from: pad, through: 1, by: -1) {
            out.append(left.intercept - left.slope * Double(j))
        }
        out.append(contentsOf: x)
        let lastX = Double(k - 1)
        for j in 1...pad {
            out.append(right.intercept + right.slope * (lastX + Double(j)))
        }
        return out
    }

    /// Least-squares line over indices 0..<count.
    static func lineFit(_ y: [Double]) -> (intercept: Double, slope: Double) {
        let n = Double(y.count)
        guard y.count > 1 else { return (y.first ?? 0, 0) }
        let meanX = (n - 1) / 2
        let meanY = y.reduce(0, +) / n
        var sxy = 0.0
        var sxx = 0.0
        for (i, v) in y.enumerated() {
            let dx = Double(i) - meanX
            sxy += dx * (v - meanY)
            sxx += dx * dx
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        return (meanY - slope * meanX, slope)
    }

    private static func boxFilter(_ x: [Double], half: Int) -> [Double] {
        let n = x.count
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
        return (0..<n).map { i in
            let lo = max(0, i - half)
            let hi = min(n - 1, i + half)
            return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
        }
    }

    private static func gaussianFilter(_ x: [Double], half: Int, sigma: Double) -> [Double] {
        let n = x.count
        let s = max(0.5, sigma)
        let weights = (-half...half).map { exp(-Double($0 * $0) / (2 * s * s)) }
        return (0..<n).map { i in
            var sum = 0.0
            var wsum = 0.0
            for (k, w) in zip(-half...half, weights) {
                let j = i + k
                guard j >= 0, j < n else { continue }
                sum += x[j] * w
                wsum += w
            }
            return sum / wsum
        }
    }

    private static func trimmedMeanFilter(_ x: [Double], half: Int, trim: Double) -> [Double] {
        let n = x.count
        return (0..<n).map { i in
            let window = x[max(0, i - half)...min(n - 1, i + half)].sorted()
            let drop = Int(Double(window.count) * trim)
            let kept = window[drop..<(window.count - drop)]
            return kept.reduce(0, +) / Double(kept.count)
        }
    }

    static func median(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        let sorted = x.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        min(limit, max(-limit, value))
    }
}
