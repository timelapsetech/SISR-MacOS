import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SISRKit

enum TestSupport {
    /// Thread-safe progress sink for `Renderer.render` callbacks in tests.
    final class ProgressProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var _finished = false
        private var _sawDeflicker = false
        private var _maxTotal = 0
        private var _finishedTotal = 0

        var finished: Bool {
            lock.lock(); defer { lock.unlock() }
            return _finished
        }

        var sawDeflicker: Bool {
            lock.lock(); defer { lock.unlock() }
            return _sawDeflicker
        }

        var maxTotal: Int {
            lock.lock(); defer { lock.unlock() }
            return _maxTotal
        }

        var finishedTotal: Int {
            lock.lock(); defer { lock.unlock() }
            return _finishedTotal
        }

        func observe(_ progress: RenderProgress) {
            lock.lock()
            defer { lock.unlock() }
            _maxTotal = max(_maxTotal, progress.framesTotal)
            if progress.statusMessage?.contains("deflicker") == true {
                _sawDeflicker = true
            }
            if progress.isFinished {
                _finished = true
                _finishedTotal = progress.framesTotal
            }
        }

        var handler: @Sendable (RenderProgress) -> Void {
            { [self] progress in
                self.observe(progress)
            }
        }
    }

    struct RGBA: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8

        var luma: Double {
            (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
        }
    }

    enum SampleError: Error {
        case context
        case imageWrite
        case missingImage
    }

    /// Temporary directory that callers should delete with `defer`.
    static func makeTempDir(prefix: String = "sisr-test") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw SampleError.imageWrite
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw SampleError.imageWrite
        }
    }

    /// Solid-fill RGB image (sRGB / device RGB).
    static func makeSolidImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SampleError.context
        }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else { throw SampleError.missingImage }
        return image
    }

    /// Left half `left`, right half `right` (useful for crop sampling).
    static func makeSplitHorizontalImage(
        width: Int,
        height: Int,
        left: (CGFloat, CGFloat, CGFloat),
        right: (CGFloat, CGFloat, CGFloat)
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SampleError.context
        }
        let mid = width / 2
        ctx.setFillColor(red: left.0, green: left.1, blue: left.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: mid, height: height))
        ctx.setFillColor(red: right.0, green: right.1, blue: right.2, alpha: 1)
        ctx.fill(CGRect(x: mid, y: 0, width: width - mid, height: height))
        guard let image = ctx.makeImage() else { throw SampleError.missingImage }
        return image
    }

    /// Numbered PNG sequence `prefix_0001.png` … suitable for `SequenceScanner` / render.
    static func writeNumberedSequence(
        directory: URL,
        frameCount: Int,
        width: Int,
        height: Int,
        prefix: String = "clip",
        paint: (_ index: Int, _ ctx: CGContext, _ size: CGSize) -> Void
    ) throws -> ImageSequenceSpec {
        var frames: [ImageSequenceFrame] = []
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for i in 1...frameCount {
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw SampleError.context
            }
            paint(i - 1, ctx, CGSize(width: width, height: height))
            guard let cg = ctx.makeImage() else { throw SampleError.missingImage }
            let name = String(format: "%@_%04d.png", prefix, i)
            let url = directory.appendingPathComponent(name)
            try writePNG(cg, to: url)
            frames.append(ImageSequenceFrame(url: url, frameNumber: i))
        }
        return ImageSequenceSpec(
            directory: directory,
            prefix: "\(prefix)_",
            numberWidth: 4,
            ext: ".png",
            startNumber: 1,
            frames: frames
        )
    }

    static func writeSolidSequence(
        directory: URL,
        frameCount: Int,
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        prefix: String = "clip"
    ) throws -> ImageSequenceSpec {
        try writeNumberedSequence(
            directory: directory,
            frameCount: frameCount,
            width: width,
            height: height,
            prefix: prefix
        ) { _, ctx, size in
            ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Sample one pixel in bottom-left Core Graphics coordinates.
    static func samplePixel(_ image: CGImage, at point: CGPoint) throws -> RGBA {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SampleError.context
        }
        ctx.interpolationQuality = .none
        ctx.translateBy(x: -point.x.rounded(.down), y: -point.y.rounded(.down))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return RGBA(r: pixel[0], g: pixel[1], b: pixel[2], a: pixel[3])
    }

    static func sampleCenter(_ image: CGImage) throws -> RGBA {
        try samplePixel(
            image,
            at: CGPoint(x: Double(image.width) / 2, y: Double(image.height) / 2)
        )
    }

    static func pipelineInput(
        imageURL: URL,
        outputSize: PixelSize,
        crop: CropState = .fullFrame,
        adjustments: Adjustments = .identity,
        overlay: OverlayType = .none,
        overlayText: String = "",
        overlayBackgroundOpacity: Double = 0.5,
        showOriginal: Bool = false,
        compositionPreview: Bool = false,
        exposureBias: Double = 0
    ) -> FramePipelineInput {
        FramePipelineInput(
            imageURL: imageURL,
            crop: crop,
            adjustments: adjustments,
            outputSize: outputSize,
            overlay: overlay,
            overlayText: overlayText,
            overlayBackgroundOpacity: overlayBackgroundOpacity,
            showOriginal: showOriginal,
            compositionPreview: compositionPreview,
            exposureBias: exposureBias
        )
    }

    static func renderSnapshot(
        sequence: ImageSequenceSpec,
        sourceSize: CGSize,
        outputSize: PixelSize,
        codec: OutputCodec,
        outputDirectory: URL,
        crop: CropState = .fullFrame,
        adjustments: Adjustments = .identity,
        overlay: OverlayType = .none,
        timeline: TimelineRange? = nil,
        frameDates: [String] = [],
        outputBaseName: String = "smoke"
    ) -> SequenceProjectSnapshot {
        var render = RenderSettings(
            preset: .custom,
            customSize: outputSize,
            codec: codec,
            overlay: overlay,
            outputDirectoryPath: outputDirectory.path,
            outputBaseName: outputBaseName
        )
        render.fps = codec == .gif ? 4 : 30
        let range = timeline ?? TimelineRange(inIndex: 0, outIndex: max(0, sequence.frameCount - 1))
        return SequenceProjectSnapshot(
            sequence: sequence,
            crop: crop,
            adjustments: adjustments,
            render: render,
            timeline: range,
            outputSize: outputSize,
            frameDates: frameDates
        )
    }
}
