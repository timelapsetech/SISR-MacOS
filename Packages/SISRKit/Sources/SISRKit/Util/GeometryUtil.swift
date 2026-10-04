import CoreGraphics
import Foundation

public enum GeometryUtil {
    /// Round down to the nearest even integer (codec-friendly).
    public static func even(_ value: Int) -> Int {
        value - (value % 2)
    }

    /// Convert a CGFloat to a non-negative Int without trapping on NaN/Inf.
    public static func safeInt(_ value: CGFloat) -> Int {
        guard value.isFinite else { return 0 }
        if value <= 0 { return 0 }
        if value >= CGFloat(Int.max) { return Int.max - (Int.max % 2) }
        return Int(value.rounded(.down))
    }

    public static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(even(safeInt(size.width))),
            height: CGFloat(even(safeInt(size.height)))
        )
    }

    public static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    public static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard value.isFinite else { return minValue }
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    /// Fit `inner` inside `outer` while preserving aspect ratio.
    public static func aspectFit(_ inner: CGSize, in outer: CGSize) -> CGSize {
        guard isValidSize(inner), isValidSize(outer) else {
            return .zero
        }
        let scale = min(outer.width / inner.width, outer.height / inner.height)
        guard scale.isFinite else { return .zero }
        return evenSize(CGSize(width: inner.width * scale, height: inner.height * scale))
    }

    /// Largest even rect of `aspect` centered in `bounds`.
    public static func centeredAspectRect(in bounds: CGSize, aspect: CGFloat) -> CGRect {
        guard isValidSize(bounds), aspect.isFinite, aspect > 0 else { return .zero }
        let boundsAspect = bounds.width / bounds.height
        guard boundsAspect.isFinite else { return .zero }
        let width: CGFloat
        let height: CGFloat
        if boundsAspect > aspect {
            height = bounds.height
            width = height * aspect
        } else {
            width = bounds.width
            height = width / aspect
        }
        guard width.isFinite, height.isFinite else { return .zero }
        let evenW = CGFloat(even(safeInt(width)))
        let evenH = CGFloat(even(safeInt(height)))
        let x = ((bounds.width - evenW) / 2).rounded(.down)
        let y = ((bounds.height - evenH) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: evenW, height: evenH)
    }
}
