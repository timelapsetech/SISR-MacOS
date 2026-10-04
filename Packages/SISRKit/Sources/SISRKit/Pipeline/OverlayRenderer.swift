import AppKit
import CoreGraphics
import CoreImage
import Foundation

public enum OverlayRenderer {
    /// Relative margin from crop/output edges (matches historical burn-in layout).
    public static let edgeMarginFraction: CGFloat = 0.05

    public static func drawOverlay(
        on image: CIImage,
        overlay: OverlayType,
        text: String,
        outputSize: PixelSize,
        numberWidth _: Int,
        backgroundOpacity: Double = 0.5
    ) -> CIImage {
        guard overlay != .none, !text.isEmpty || overlay == .frame else { return image }

        let width = outputSize.width
        let height = outputSize.height
        guard width > 0, height > 0 else { return image }

        let displayText: String
        switch overlay {
        case .none:
            return image
        case .date, .frame:
            displayText = text
        }

        let layout = layoutMetrics(
            overlay: overlay,
            text: displayText,
            canvasWidth: width,
            canvasHeight: height
        )

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return image }
        // Match point size to pixel size so 1pt == 1px when drawing overlays.
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return image
        }
        NSGraphicsContext.current = nsCtx
        let cg = nsCtx.cgContext

        // Must start fully transparent. An uninitialized / opaque buffer makes
        // source-over black@opacity blend to light gray and look washed out in render.
        cg.setBlendMode(.copy)
        cg.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let opacity = RenderSettings.clampOpacity(backgroundOpacity)
        cg.setFillColor(gray: 0, alpha: CGFloat(opacity))
        cg.fill(layout.boxRect)

        // Opaque white text over the translucent plate (normal compositing).
        cg.setBlendMode(.normal)
        let font = NSFont(name: "SFMono-Regular", size: layout.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: layout.fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let nsText = NSAttributedString(string: displayText, attributes: attrs)
        let textOrigin = CGPoint(
            x: layout.boxRect.minX + layout.padding,
            y: layout.boxRect.minY + layout.padding
        )
        nsText.draw(at: textOrigin)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else { return image }
        // Explicit premultiplied alpha so CI compositing matches SwiftUI's opacity plate.
        let overlayCI = CIImage(cgImage: cgImage)
        return overlayCI.composited(over: image)
    }

    /// Font size, padding, and badge rect in canvas pixel coordinates (Y-up, bottom-left origin).
    public static func layoutMetrics(
        overlay: OverlayType,
        text: String,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> OverlayLayoutMetrics {
        let fontSize = CGFloat(DateOverlayFormatter.overlayFontSize(
            for: text,
            frameWidth: canvasWidth,
            frameHeight: canvasHeight
        ))
        let padding = fontSize * 0.25
        let font = NSFont(name: "SFMono-Regular", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = NSAttributedString(string: text, attributes: attrs).size()
        let boxSize = CGSize(
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
        let canvas = CGSize(width: canvasWidth, height: canvasHeight)
        let origin = boxOrigin(overlay: overlay, canvas: canvas, boxSize: boxSize)
        return OverlayLayoutMetrics(
            fontSize: fontSize,
            padding: padding,
            boxRect: CGRect(origin: origin, size: boxSize)
        )
    }

    /// Badge origin in a canvas with bottom-left origin (Core Graphics / AppKit).
    public static func boxOrigin(
        overlay: OverlayType,
        canvas: CGSize,
        boxSize: CGSize
    ) -> CGPoint {
        let marginX = canvas.width * edgeMarginFraction
        let marginY = canvas.height * edgeMarginFraction
        switch overlay {
        case .date:
            return CGPoint(
                x: canvas.width - boxSize.width - marginX,
                y: marginY
            )
        case .frame:
            return CGPoint(
                x: (canvas.width - boxSize.width) / 2,
                y: canvas.height - boxSize.height - marginY
            )
        case .none:
            return .zero
        }
    }

    /// Convert a bottom-left-origin rect into top-left-origin coordinates for SwiftUI.
    public static func topLeftBoxRect(
        overlay: OverlayType,
        text: String,
        canvasSize: CGSize
    ) -> CGRect {
        let w = max(1, Int(canvasSize.width.rounded()))
        let h = max(1, Int(canvasSize.height.rounded()))
        let metrics = layoutMetrics(
            overlay: overlay,
            text: text,
            canvasWidth: w,
            canvasHeight: h
        )
        let bl = metrics.boxRect
        return CGRect(
            x: bl.origin.x,
            y: CGFloat(h) - bl.origin.y - bl.size.height,
            width: bl.size.width,
            height: bl.size.height
        )
    }

    public static func frameOverlayText(
        indexInRender: Int,
        sourceFrameNumber: Int,
        mode: FrameNumberMode,
        pad: Int,
        totalFrames: Int
    ) -> String {
        let value: Int
        switch mode {
        case .countFromInPoint:
            value = indexInRender + 1
        case .useSourceNumbers:
            value = sourceFrameNumber
        }
        let width = max(1, pad, String(totalFrames).count)
        return String(format: "FRAME %0\(width)d", value)
    }
}

public struct OverlayLayoutMetrics: Sendable, Equatable {
    public var fontSize: CGFloat
    public var padding: CGFloat
    public var boxRect: CGRect

    public init(fontSize: CGFloat, padding: CGFloat, boxRect: CGRect) {
        self.fontSize = fontSize
        self.padding = padding
        self.boxRect = boxRect
    }
}
