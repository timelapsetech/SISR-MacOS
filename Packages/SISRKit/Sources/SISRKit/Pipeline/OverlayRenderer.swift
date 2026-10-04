import AppKit
import CoreGraphics
import CoreImage
import Foundation

public enum OverlayRenderer {
    /// Relative margin from crop/output edges (matches historical burn-in layout).
    public static let edgeMarginFraction: CGFloat = 0.05

    /// Burn the overlay into a CGImage using Core Graphics source-over blending.
    ///
    /// This matches SwiftUI's `Color.black.opacity(_:)` plate (gamma-encoded compositing).
    /// Core Image's `composited(over:)` blends in a linear working space and makes the
    /// same alpha look washed out / less solid than the viewer preview.
    public static func burnIn(
        on image: CGImage,
        overlay: OverlayType,
        text: String,
        backgroundOpacity: Double = 0.5
    ) -> CGImage {
        guard overlay != .none, !text.isEmpty || overlay == .frame else { return image }

        let width = image.width
        let height = image.height
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

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: canvas)

        let opacity = RenderSettings.clampOpacity(backgroundOpacity)
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: CGFloat(opacity))
        ctx.fill(layout.boxRect)

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
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

        return ctx.makeImage() ?? image
    }

    /// Bake overlay into a CI frame by rendering through CG (gamma-correct alpha).
    public static func drawOverlay(
        on image: CIImage,
        overlay: OverlayType,
        text: String,
        outputSize: PixelSize,
        numberWidth _: Int,
        backgroundOpacity: Double = 0.5,
        context: CIContext
    ) -> CIImage {
        guard overlay != .none, !text.isEmpty || overlay == .frame else { return image }
        let rect = CGRect(origin: .zero, size: outputSize.cgSize)
        guard rect.width > 0, rect.height > 0,
              let cg = context.createCGImage(image, from: rect)
        else {
            return image
        }
        let burned = burnIn(
            on: cg,
            overlay: overlay,
            text: text,
            backgroundOpacity: backgroundOpacity
        )
        return CIImage(cgImage: burned)
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
