import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

public struct FramePipelineInput: Sendable {
    public var imageURL: URL
    public var crop: CropState
    public var adjustments: Adjustments
    public var outputSize: PixelSize
    public var overlay: OverlayType
    public var overlayText: String
    public var overlayBackgroundOpacity: Double
    public var showOriginal: Bool
    /// Full-frame preview for the viewer (adjustments on, crop/output scale off).
    public var compositionPreview: Bool
    public var exposureBias: Double

    public init(
        imageURL: URL,
        crop: CropState,
        adjustments: Adjustments,
        outputSize: PixelSize,
        overlay: OverlayType = .none,
        overlayText: String = "",
        overlayBackgroundOpacity: Double = 0.5,
        showOriginal: Bool = false,
        compositionPreview: Bool = false,
        exposureBias: Double = 0
    ) {
        self.imageURL = imageURL
        self.crop = crop
        self.adjustments = adjustments
        self.outputSize = outputSize
        self.overlay = overlay
        self.overlayText = overlayText
        self.overlayBackgroundOpacity = overlayBackgroundOpacity
        self.showOriginal = showOriginal
        self.compositionPreview = compositionPreview
        self.exposureBias = exposureBias
    }
}

public final class FramePipeline: @unchecked Sendable {
    private let context: CIContext

    public init(context: CIContext? = nil) {
        self.context = context ?? CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
        ])
    }

    public var ciContext: CIContext { context }

    public func makeImage(from input: FramePipelineInput) -> CIImage? {
        guard var image = loadCIImage(url: input.imageURL) else { return nil }

        if input.showOriginal {
            return cropFull(image)
        }

        image = applyOrientation(image, crop: input.crop)
        image = applyColor(image, color: input.adjustments.color, exposureBias: input.exposureBias)
        image = applyDetail(image, detail: input.adjustments.detail)

        // Viewer composition: full frame with a crop overlay drawn in UI, not baked in.
        if input.compositionPreview {
            return cropFull(image)
        }

        image = applyStraightenAndCrop(image, crop: input.crop)
        image = scaleToOutput(image, size: input.outputSize)

        if input.overlay != .none {
            // Bake via Core Graphics so plate alpha matches SwiftUI preview
            // (CI linear compositing looks washed out for the same opacity).
            image = OverlayRenderer.drawOverlay(
                on: image,
                overlay: input.overlay,
                text: input.overlayText,
                outputSize: input.outputSize,
                numberWidth: 0,
                backgroundOpacity: input.overlayBackgroundOpacity,
                context: context
            )
        }
        return image
    }

    public func renderCGImage(from input: FramePipelineInput) -> CGImage? {
        // Avoid CI→CG→overlay→CI→CG when burning in: composite the plate in CG once.
        let wantsOverlay = input.overlay != .none && !input.compositionPreview && !input.showOriginal
        if wantsOverlay {
            var overlayInput = input
            overlayInput.overlay = .none
            guard let base = makeImage(from: overlayInput) else { return nil }
            let rect = CGRect(origin: .zero, size: input.outputSize.cgSize)
            guard let cg = context.createCGImage(base, from: rect) else { return nil }
            return OverlayRenderer.burnIn(
                on: cg,
                overlay: input.overlay,
                text: input.overlayText,
                backgroundOpacity: input.overlayBackgroundOpacity
            )
        }

        guard let ci = makeImage(from: input) else { return nil }
        let rect: CGRect
        if input.compositionPreview || input.showOriginal {
            rect = ci.extent.integral
        } else {
            rect = CGRect(origin: .zero, size: input.outputSize.cgSize)
        }
        return context.createCGImage(ci, from: rect)
    }

    /// Tiny progress thumbnail from an already-built CIImage (avoids a second full pipeline pass).
    public func renderProgressThumbnail(from image: CIImage, maxLongEdge: CGFloat = 240) -> CGImage? {
        let extent = image.extent
        let longEdge = max(extent.width, extent.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxLongEdge / longEdge)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translated = scaled.transformed(
            by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY)
        )
        return context.createCGImage(translated, from: translated.extent.integral)
    }

    /// Tiny progress thumbnail from a full-size CGImage via a cheap downsample draw.
    public func renderProgressThumbnail(from cgImage: CGImage, maxLongEdge: CGFloat = 240) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let longEdge = max(w, h)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxLongEdge / longEdge)
        let tw = max(1, Int((w * scale).rounded()))
        let th = max(1, Int((h * scale).rounded()))
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: tw,
            height: th,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    public func clearCaches() {
        context.clearCaches()
    }

    /// Apply flip / 90° orientation to an already-decoded preview thumbnail (no grade).
    public func orientPreview(_ cgImage: CGImage, crop: CropState) -> CGImage? {
        let needsOrient =
            crop.flipHorizontal
            || crop.flipVertical
            || (((crop.rotationQuarterTurns % 4) + 4) % 4) != 0
        guard needsOrient else { return cgImage }
        let oriented = applyOrientation(CIImage(cgImage: cgImage), crop: crop)
        return context.createCGImage(oriented, from: oriented.extent.integral)
    }

    /// Crop + scale a decoded thumbnail for Preview Full playback (no grade / overlay).
    /// `outputSize` should already be capped to viewer resolution for smooth scrubbing.
    public func cropOutputPreview(
        _ cgImage: CGImage,
        crop: CropState,
        outputSize: PixelSize
    ) -> CGImage? {
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }
        var image = applyOrientation(CIImage(cgImage: cgImage), crop: crop)
        image = applyStraightenAndCrop(image, crop: crop)
        image = scaleToOutput(image, size: outputSize)
        let rect = CGRect(origin: .zero, size: outputSize.cgSize)
        return context.createCGImage(image, from: rect)
    }

    /// Lazy file-backed CIImage — decoded when rendered into the writer pixel buffer,
    /// avoiding an eager full-size CGImage/IOSurface per frame (CMPhoto e00002c2 storms).
    private func loadCIImage(url: URL) -> CIImage? {
        if let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: false]) {
            return image
        }
        // Fallback: decode via ImageIO without the shared cache.
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cg = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            return nil
        }
        return CIImage(cgImage: cg)
    }

    // MARK: - Stages

    private func applyOrientation(_ image: CIImage, crop: CropState) -> CIImage {
        var img = image
        if crop.flipHorizontal {
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -img.extent.width, y: 0))
        }
        if crop.flipVertical {
            img = img.transformed(by: CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -img.extent.height))
        }
        let turns = ((crop.rotationQuarterTurns % 4) + 4) % 4
        if turns != 0 {
            img = img.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2))
            img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        }
        return img
    }

    private func applyColor(_ image: CIImage, color: ColorAdjustments, exposureBias: Double) -> CIImage {
        var img = image
        let exposure = color.exposure + exposureBias
        if exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = Float(exposure)
            img = f.outputImage ?? img
        }
        if color.contrast != 0 || color.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.contrast = Float(1.0 + color.contrast)
            f.saturation = Float(1.0 + color.saturation)
            f.brightness = 0
            img = f.outputImage ?? img
        }
        if color.highlights != 0 || color.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1.0 - color.highlights)
            f.shadowAmount = Float(color.shadows)
            img = f.outputImage ?? img
        }
        if color.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = img
            f.amount = Float(color.vibrance)
            img = f.outputImage ?? img
        }
        if color.temperature != 0 || color.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            // Neutral ~6500; map −1…1 to a useful range.
            let neutral = CIVector(x: 6500, y: 0)
            let target = CIVector(
                x: 6500 + color.temperature * 1500,
                y: color.tint * 50
            )
            f.neutral = neutral
            f.targetNeutral = target
            img = f.outputImage ?? img
        }
        return img
    }

    private func applyDetail(_ image: CIImage, detail: DetailAdjustments) -> CIImage {
        var img = image
        if detail.noiseReduction > 0 {
            let f = CIFilter.noiseReduction()
            f.inputImage = img
            f.noiseLevel = Float(detail.noiseReduction * 0.05)
            f.sharpness = 0.4
            img = f.outputImage ?? img
        }
        if detail.sharpen > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = img
            f.sharpness = Float(detail.sharpen * 2)
            img = f.outputImage ?? img
        }
        if detail.vignette != 0 {
            let f = CIFilter.vignette()
            f.inputImage = img
            f.intensity = Float(detail.vignette)
            f.radius = Float(max(img.extent.width, img.extent.height) * 0.5)
            img = f.outputImage ?? img
        }
        return img
    }

    private func applyStraightenAndCrop(_ image: CIImage, crop: CropState) -> CIImage {
        let extent = image.extent
        let sourceSize = extent.size
        let pixel = crop.pixelRect(sourceSize: sourceSize)

        // Crop center in CI coordinates (bottom-left origin).
        let ciCenter = CGPoint(
            x: extent.minX + pixel.midX,
            y: extent.minY + (sourceSize.height - pixel.midY)
        )

        let degrees = crop.straightenDegrees
        let scale = StraightenGeometry.coverScale(
            sourceSize: sourceSize,
            cropRect: pixel,
            degrees: degrees
        )

        var img = image
        if abs(degrees) >= 0.001 || scale > 1.0001 {
            let radians = CGFloat(degrees) * .pi / 180
            // Scale (zoom) and rotate about the crop center. Scale > 1 only when
            // the crop sits near an edge and rotation would otherwise sample empty pixels.
            //
            // Sign: SwiftUI preview uses `.rotationEffect(-degrees)` where positive angles
            // are clockwise (Y-down). Core Image uses Y-up / CCW-positive, so matching the
            // preview’s visual direction means rotating by +degrees here — not −degrees.
            var transform = CGAffineTransform(translationX: -ciCenter.x, y: -ciCenter.y)
            transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            transform = transform.concatenating(CGAffineTransform(rotationAngle: radians))
            transform = transform.concatenating(
                CGAffineTransform(translationX: ciCenter.x, y: ciCenter.y)
            )
            img = img.transformed(by: transform)
        }

        // Axis-aligned crop window stays put in output space.
        let ciRect = CGRect(
            x: ciCenter.x - pixel.width / 2,
            y: ciCenter.y - pixel.height / 2,
            width: pixel.width,
            height: pixel.height
        )
        img = img.cropped(to: ciRect)
        return img.transformed(
            by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY)
        )
    }

    private func cropFull(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private func scaleToOutput(_ image: CIImage, size: PixelSize) -> CIImage {
        guard size.width > 0, size.height > 0 else { return image }
        let srcW = max(image.extent.width, 1)
        let srcH = max(image.extent.height, 1)
        let sx = CGFloat(size.width) / srcW
        let sy = CGFloat(size.height) / srcH

        // Prefer Lanczos when enlarging so upscaled renders stay as sharp as possible.
        if sx > 1.001 || sy > 1.001 {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = image
            filter.scale = Float(min(sx, sy))
            filter.aspectRatio = Float(sx / sy)
            if let out = filter.outputImage {
                let target = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                return out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
                    .cropped(to: target)
            }
        }

        let scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let target = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return scaled.cropped(to: target)
            .transformed(by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY))
    }
}
