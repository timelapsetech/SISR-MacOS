import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

/// Analyzes per-frame average luminance and produces exposure offsets to smooth flicker.
public struct DeflickerAnalyzer: Sendable {
    public init() {}

    /// Returns exposure bias (EV) per frame index in `urls`.
    /// Calls `progress` with (done, total) as frames are measured so UI can update.
    public func analyze(
        urls: [URL],
        settings: DeflickerSettings,
        context: CIContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
        ]),
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> [Double] {
        guard settings.enabled, !urls.isEmpty else {
            return Array(repeating: 0, count: urls.count)
        }

        let total = urls.count
        progress?(0, total)

        var luminances: [Double] = []
        luminances.reserveCapacity(total)

        for (index, url) in urls.enumerated() {
            if Task.isCancelled || isCancelled?() == true {
                throw RenderError.cancelled
            }

            let luma: Double = autoreleasepool {
                measureLuminance(url: url, context: context) ?? 0.5
            }
            luminances.append(luma)

            let done = index + 1
            // Frequent enough for a live bar without drowning the main thread.
            if done == 1 || done == total || done % 2 == 0 {
                progress?(done, total)
            }

            if index % 32 == 0 {
                context.clearCaches()
            }
            // Let cancellation and UI progress callbacks interleave.
            await Task.yield()
        }
        context.clearCaches()

        if isCancelled?() == true {
            throw RenderError.cancelled
        }

        progress?(total, total)
        return Self.biases(from: luminances, settings: settings)
    }

    /// Synchronous convenience (no progress) for tests / simple callers.
    public func analyze(
        urls: [URL],
        settings: DeflickerSettings,
        context: CIContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
        ])
    ) -> [Double] {
        guard settings.enabled, !urls.isEmpty else {
            return Array(repeating: 0, count: urls.count)
        }
        var luminances: [Double] = []
        luminances.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            autoreleasepool {
                luminances.append(measureLuminance(url: url, context: context) ?? 0.5)
            }
            if index % 32 == 0 {
                context.clearCaches()
            }
        }
        context.clearCaches()
        return Self.biases(from: luminances, settings: settings)
    }

    public static func biases(from luminances: [Double], settings: DeflickerSettings) -> [Double] {
        let window = max(3, settings.windowSize | 1) // force odd-ish
        let half = window / 2
        var targets: [Double] = []
        targets.reserveCapacity(luminances.count)

        for i in luminances.indices {
            let lo = max(0, i - half)
            let hi = min(luminances.count - 1, i + half)
            let slice = luminances[lo...hi]
            let avg = slice.reduce(0, +) / Double(slice.count)
            targets.append(avg)
        }

        return zip(luminances, targets).map { luma, target in
            guard luma > 0.001 else { return 0 }
            // EV ≈ log2(target / luma), scaled by strength
            let ev = log2(target / luma) * settings.strength
            return max(-2, min(2, ev))
        }
    }

    private func measureLuminance(url: URL, context: CIContext) -> Double? {
        guard let image = loadDownscaledCIImage(url: url, maxLongEdge: 256) else {
            return nil
        }
        let extent = image.extent
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent
        guard let out = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            out,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255
        // Rec. 709 luma
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func loadDownscaledCIImage(url: URL, maxLongEdge: CGFloat) -> CIImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxLongEdge),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return CIImage(cgImage: cg)
    }
}
