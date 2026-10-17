import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Measures per-frame luminance distribution, color, regional brightness, and camera
/// exposure on the graded, cropped output (what actually gets encoded).
public struct DeflickerAnalyzer: Sendable {
    /// Long edge of the measured output image.
    static let analysisLongEdge: CGFloat = 256

    public init() {}

    /// Measures `urls` in parallel. `progress` receives (done, total).
    public func analyze(
        urls: [URL],
        crop: CropState,
        adjustments: Adjustments,
        outputSize: PixelSize,
        pipeline: FramePipeline = FramePipeline(),
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> [DeflickerFrameStats] {
        let total = urls.count
        guard total > 0 else { return [] }
        progress?(0, total)

        let analysisSize = Self.analysisSize(for: outputSize)
        let decodeEdge = Self.decodeLongEdge(crop: crop)
        let concurrency = max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 1))

        var results = [DeflickerFrameStats?](repeating: nil, count: total)
        var done = 0
        try await withThrowingTaskGroup(of: (Int, DeflickerFrameStats?).self) { group in
            var next = 0
            func enqueue() {
                guard next < total else { return }
                let index = next
                let url = urls[index]
                next += 1
                group.addTask {
                    let stats = autoreleasepool {
                        Self.measure(
                            url: url,
                            crop: crop,
                            adjustments: adjustments,
                            analysisSize: analysisSize,
                            decodeLongEdge: decodeEdge,
                            pipeline: pipeline
                        )
                    }
                    return (index, stats)
                }
            }
            for _ in 0..<concurrency { enqueue() }

            while let (index, stats) = try await group.next() {
                if Task.isCancelled || isCancelled?() == true {
                    group.cancelAll()
                    throw RenderError.cancelled
                }
                results[index] = stats
                done += 1
                if done == 1 || done == total || done % 4 == 0 {
                    progress?(done, total)
                }
                if done % 64 == 0 {
                    pipeline.clearCaches()
                }
                enqueue()
            }
        }
        pipeline.clearCaches()

        if isCancelled?() == true {
            throw RenderError.cancelled
        }
        progress?(total, total)
        return Self.fillingGaps(results)
    }

    /// Unreadable frames borrow their nearest neighbor's stats so they are left uncorrected.
    static func fillingGaps(_ results: [DeflickerFrameStats?]) -> [DeflickerFrameStats] {
        guard let firstKnown = results.first(where: { $0 != nil }) ?? nil else {
            return results.map { _ in neutralStats }
        }
        var last = firstKnown
        return results.map { stats in
            if let stats { last = stats }
            return last
        }
    }

    static let neutralStats = DeflickerFrameStats(
        regions: DeflickerMetering.allCases.map { _ in
            DeflickerRegionStats(
                quantiles: [Float](repeating: -2.5, count: DeflickerFrameStats.quantileCount),
                chromaRG: 0,
                chromaBG: 0
            )
        },
        grid: [Float](repeating: -2.5, count: DeflickerFrameStats.gridColumns * DeflickerFrameStats.gridRows),
        cameraExposure: nil
    )

    static func analysisSize(for output: PixelSize) -> PixelSize {
        let w = CGFloat(max(1, output.width))
        let h = CGFloat(max(1, output.height))
        let scale = min(1, analysisLongEdge / max(w, h))
        return PixelSize(
            width: max(DeflickerFrameStats.gridColumns, Int((w * scale).rounded())),
            height: max(DeflickerFrameStats.gridRows, Int((h * scale).rounded()))
        )
    }

    /// Decode enough source pixels that a tight crop still fills the analysis image.
    static func decodeLongEdge(crop: CropState) -> CGFloat {
        let fraction = max(0.05, max(crop.normalizedRect.width, crop.normalizedRect.height))
        return min(1536, max(384, (analysisLongEdge * 1.5) / fraction))
    }

    // MARK: - Single frame

    static func measure(
        url: URL,
        crop: CropState,
        adjustments: Adjustments,
        analysisSize: PixelSize,
        decodeLongEdge: CGFloat,
        pipeline: FramePipeline
    ) -> DeflickerFrameStats? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(decodeLongEdge),
            // The render pipeline ignores EXIF orientation; match it so crops line up.
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let graded = pipeline.gradedOutput(
            from: CIImage(cgImage: cg),
            crop: crop,
            adjustments: adjustments,
            outputSize: analysisSize
        )
        let w = analysisSize.width
        let h = analysisSize.height
        var pixels = [Float](repeating: 0, count: w * h * 4)
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            pipeline.ciContext.render(
                graded,
                toBitmap: base,
                rowBytes: w * 16,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                format: .RGBAf,
                colorSpace: linear
            )
        }
        var stats = statistics(linearRGBA: pixels, width: w, height: h)
        stats.cameraExposure = cameraExposure(source: source)
        return stats
    }

    /// Stats from a top-row-first linear RGBA float buffer.
    static func statistics(linearRGBA px: [Float], width w: Int, height h: Int) -> DeflickerFrameStats {
        let count = w * h
        var logLum = [Float](repeating: 0, count: count)
        var midtone = [Bool](repeating: false, count: count)
        var logRG = [Float](repeating: 0, count: count)
        var logBG = [Float](repeating: 0, count: count)
        let lowClip: Float = 0.002
        let highClip: Float = 0.92
        for i in 0..<count {
            let r = max(0, px[i * 4])
            let g = max(0, px[i * 4 + 1])
            let b = max(0, px[i * 4 + 2])
            let y = DeflickerColor.luminance(r: r, g: g, b: b)
            logLum[i] = log2(max(y, DeflickerColor.minLuminance))
            if min(r, g, b) > lowClip, max(r, g, b) < highClip {
                midtone[i] = true
                logRG[i] = log2(r) - log2(g)
                logBG[i] = log2(b) - log2(g)
            }
        }

        func regionStats(_ include: (Int, Int) -> Bool) -> DeflickerRegionStats {
            var values: [Float] = []
            values.reserveCapacity(count)
            var rg: Double = 0
            var bg: Double = 0
            var colorCount = 0
            for y in 0..<h {
                for x in 0..<w where include(x, y) {
                    let i = y * w + x
                    values.append(logLum[i])
                    if midtone[i] {
                        rg += Double(logRG[i])
                        bg += Double(logBG[i])
                        colorCount += 1
                    }
                }
            }
            if values.isEmpty { values = logLum }
            values.sort()
            let quantiles = DeflickerFrameStats.quantileLevels.map { p -> Float in
                let pos = p * Double(values.count - 1)
                let lo = Int(pos.rounded(.down))
                let hi = min(values.count - 1, lo + 1)
                let t = Float(pos - Double(lo))
                return values[lo] + (values[hi] - values[lo]) * t
            }
            let n = Double(max(1, colorCount))
            return DeflickerRegionStats(
                quantiles: quantiles,
                chromaRG: colorCount > 0 ? Float(rg / n) : 0,
                chromaBG: colorCount > 0 ? Float(bg / n) : 0
            )
        }

        let regions = DeflickerMetering.allCases.map { metering -> DeflickerRegionStats in
            switch metering {
            case .fullFrame:
                return regionStats { _, _ in true }
            case .ignoreSky:
                return regionStats { _, y in y >= h / 3 }
            case .center:
                return regionStats { x, y in
                    x >= w / 4 && x < w - w / 4 && y >= h / 4 && y < h - h / 4
                }
            }
        }

        let cols = DeflickerFrameStats.gridColumns
        let rows = DeflickerFrameStats.gridRows
        var sums = [Double](repeating: 0, count: cols * rows)
        var counts = [Int](repeating: 0, count: cols * rows)
        for y in 0..<h {
            let r = min(rows - 1, y * rows / h)
            for x in 0..<w {
                let c = min(cols - 1, x * cols / w)
                sums[r * cols + c] += Double(logLum[y * w + x])
                counts[r * cols + c] += 1
            }
        }
        let grid = (0..<(cols * rows)).map { Float(sums[$0] / Double(max(1, counts[$0]))) }

        return DeflickerFrameStats(regions: regions, grid: grid, cameraExposure: nil)
    }

    /// log2(t · ISO/100 / N²) — relative sensor exposure in stops.
    static func cameraExposure(source: CGImageSource) -> Double? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let time = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
              time > 0
        else { return nil }
        var stops = log2(time)
        if let isoList = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber],
           let iso = isoList.first?.doubleValue, iso > 0
        {
            stops += log2(iso / 100)
        }
        if let aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue, aperture > 0 {
            stops -= 2 * log2(aperture)
        }
        return stops
    }
}
