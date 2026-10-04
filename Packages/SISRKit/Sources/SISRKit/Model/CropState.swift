import CoreGraphics
import Foundation

public enum CropAlign: String, Codable, Sendable, CaseIterable {
    case center
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// Normalized crop rect in source image coordinates (0…1), plus transform.
public struct CropState: Codable, Equatable, Sendable {
    /// Normalized rect in unit space of the oriented source image.
    public var normalizedRect: CGRect
    /// Straighten angle in degrees (−45…45).
    public var straightenDegrees: Double
    public var rotationQuarterTurns: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var aspectLock: AspectRatioLock

    public static let fullFrame = CropState(
        normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        straightenDegrees: 0,
        rotationQuarterTurns: 0,
        flipHorizontal: false,
        flipVertical: false,
        aspectLock: .matchSource
    )

    public init(
        normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        straightenDegrees: Double = 0,
        rotationQuarterTurns: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        aspectLock: AspectRatioLock = .matchSource
    ) {
        self.normalizedRect = normalizedRect
        self.straightenDegrees = straightenDegrees
        self.rotationQuarterTurns = rotationQuarterTurns
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.aspectLock = aspectLock
    }

    public func pixelRect(sourceSize: CGSize) -> CGRect {
        guard GeometryUtil.isValidSize(sourceSize) else { return .zero }
        let r = sanitizedNormalizedRect
        var rect = CGRect(
            x: r.origin.x * sourceSize.width,
            y: r.origin.y * sourceSize.height,
            width: r.size.width * sourceSize.width,
            height: r.size.height * sourceSize.height
        )
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite
        else {
            return .zero
        }
        rect.size = GeometryUtil.evenSize(rect.size)
        rect.origin.x = CGFloat(GeometryUtil.safeInt(rect.origin.x))
        rect.origin.y = CGFloat(GeometryUtil.safeInt(rect.origin.y))
        return rect
    }

    public func pixelSize(sourceSize: CGSize) -> PixelSize {
        let r = pixelRect(sourceSize: sourceSize)
        return PixelSize(
            width: GeometryUtil.safeInt(r.width),
            height: GeometryUtil.safeInt(r.height)
        ).even
    }

    public mutating func setAspectLock(_ lock: AspectRatioLock, sourceSize: CGSize) {
        aspectLock = lock
        applyAspectConstraint(sourceSize: sourceSize, align: .center, preferLargest: true)
    }

    public mutating func applyAspectConstraint(
        sourceSize: CGSize,
        align: CropAlign,
        preferLargest: Bool = false
    ) {
        guard GeometryUtil.isValidSize(sourceSize) else { return }

        let aspect: CGFloat
        switch aspectLock {
        case .free:
            return
        case .matchSource:
            aspect = sourceSize.width / sourceSize.height
            guard aspect.isFinite, aspect > 0 else { return }
        default:
            guard let a = aspectLock.aspect, a.isFinite, a > 0 else { return }
            aspect = a
        }

        let current = pixelRect(sourceSize: sourceSize)
        let largest = GeometryUtil.centeredAspectRect(in: sourceSize, aspect: aspect)
        var target: CGRect

        if preferLargest
            || current.width >= sourceSize.width * 0.98
            || current.height >= sourceSize.height * 0.98
        {
            target = largest
        } else {
            let currentAspect = current.width / max(current.height, 1)
            if abs(currentAspect - aspect) > 0.001 {
                var w = current.width
                var h = w / aspect
                if h > current.height {
                    h = current.height
                    w = h * aspect
                }
                if w > largest.width {
                    w = largest.width
                    h = largest.height
                }
                w = CGFloat(GeometryUtil.even(GeometryUtil.safeInt(w)))
                h = CGFloat(GeometryUtil.even(GeometryUtil.safeInt(h)))
                var x = current.midX - w / 2
                var y = current.midY - h / 2
                x = GeometryUtil.clamp(x, min: 0, max: sourceSize.width - w)
                y = GeometryUtil.clamp(y, min: 0, max: sourceSize.height - h)
                target = CGRect(x: x, y: y, width: w, height: h)
            } else {
                target = current
            }
        }

        guard GeometryUtil.isValidSize(target.size) else { return }
        target = alignRect(target, in: sourceSize, align: align)
        setNormalizedRect(from: target, sourceSize: sourceSize)
    }

    public mutating func align(_ align: CropAlign, sourceSize: CGSize) {
        guard GeometryUtil.isValidSize(sourceSize) else { return }
        let current = pixelRect(sourceSize: sourceSize)
        let aligned = alignRect(current, in: sourceSize, align: align)
        setNormalizedRect(from: aligned, sourceSize: sourceSize)
    }

    /// Scale crop around its center (zoom in = smaller crop).
    public mutating func zoom(factor: CGFloat, sourceSize: CGSize) {
        guard factor.isFinite, factor > 0, GeometryUtil.isValidSize(sourceSize) else { return }
        var rect = pixelRect(sourceSize: sourceSize)
        let cx = rect.midX
        let cy = rect.midY
        var w = rect.width / factor
        var h = rect.height / factor
        if let aspect = self.resolvedAspect(sourceSize: sourceSize) {
            h = w / aspect
        }
        w = max(2, CGFloat(GeometryUtil.even(GeometryUtil.safeInt(w))))
        h = max(2, CGFloat(GeometryUtil.even(GeometryUtil.safeInt(h))))
        w = min(w, sourceSize.width)
        h = min(h, sourceSize.height)
        var x = cx - w / 2
        var y = cy - h / 2
        x = GeometryUtil.clamp(x, min: 0, max: sourceSize.width - w)
        y = GeometryUtil.clamp(y, min: 0, max: sourceSize.height - h)
        rect = CGRect(x: x, y: y, width: w, height: h)
        setNormalizedRect(from: rect, sourceSize: sourceSize)
    }

    public mutating func rotateLeft() {
        setQuarterTurns(rotationQuarterTurns - 1)
    }

    public mutating func rotateRight() {
        setQuarterTurns(rotationQuarterTurns + 1)
    }

    /// Set discrete orientation to `turns` × 90° (normalized to 0…3).
    public mutating func setQuarterTurns(_ turns: Int) {
        rotationQuarterTurns = ((turns % 4) + 4) % 4
    }

    /// Discrete orientation in degrees: 0, 90, 180, or 270.
    public var rotationDegrees: Int {
        (((rotationQuarterTurns % 4) + 4) % 4) * 90
    }

    /// Source size after 90° orientation (width/height swap on odd quarter turns).
    public func orientedSize(of size: CGSize) -> CGSize {
        let turns = ((rotationQuarterTurns % 4) + 4) % 4
        if turns % 2 == 1 {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }

    /// Set crop from a rect in source-pixel (top-left) coordinates.
    public mutating func setPixelRect(_ rect: CGRect, sourceSize: CGSize, constrainAspect: Bool = true) {
        guard GeometryUtil.isValidSize(sourceSize) else { return }
        var r = rect.standardized
        r = r.intersection(CGRect(origin: .zero, size: sourceSize))
        guard r.width.isFinite, r.height.isFinite, r.width >= 2, r.height >= 2 else { return }

        if constrainAspect, let aspect = resolvedAspect(sourceSize: sourceSize) {
            // Fit the locked aspect inside the drawn rect, anchored to the drag start corner-ish center.
            var w = r.width
            var h = w / aspect
            if h > r.height {
                h = r.height
                w = h * aspect
            }
            w = max(2, CGFloat(GeometryUtil.even(GeometryUtil.safeInt(w))))
            h = max(2, CGFloat(GeometryUtil.even(GeometryUtil.safeInt(h))))
            let x = GeometryUtil.clamp(r.midX - w / 2, min: 0, max: sourceSize.width - w)
            let y = GeometryUtil.clamp(r.midY - h / 2, min: 0, max: sourceSize.height - h)
            r = CGRect(x: x, y: y, width: w, height: h)
        } else {
            r.size = GeometryUtil.evenSize(r.size)
            r.origin.x = GeometryUtil.clamp(
                CGFloat(GeometryUtil.safeInt(r.origin.x)),
                min: 0,
                max: sourceSize.width - r.width
            )
            r.origin.y = GeometryUtil.clamp(
                CGFloat(GeometryUtil.safeInt(r.origin.y)),
                min: 0,
                max: sourceSize.height - r.height
            )
        }

        setNormalizedRect(from: r, sourceSize: sourceSize)
    }

    public enum Handle: Int, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }

    /// Resize by dragging a handle; `fixed` corner/edge stays put when possible.
    public mutating func resize(
        handle: Handle,
        toPoint pointInSource: CGPoint,
        sourceSize: CGSize
    ) {
        let r = pixelRect(sourceSize: sourceSize)
        let minSize: CGFloat = 16
        var x0 = r.minX
        var y0 = r.minY
        var x1 = r.maxX
        var y1 = r.maxY
        let px = GeometryUtil.clamp(pointInSource.x, min: 0, max: sourceSize.width)
        let py = GeometryUtil.clamp(pointInSource.y, min: 0, max: sourceSize.height)

        switch handle {
        case .topLeft:
            x0 = min(px, x1 - minSize)
            y0 = min(py, y1 - minSize)
        case .topRight:
            x1 = max(px, x0 + minSize)
            y0 = min(py, y1 - minSize)
        case .bottomLeft:
            x0 = min(px, x1 - minSize)
            y1 = max(py, y0 + minSize)
        case .bottomRight:
            x1 = max(px, x0 + minSize)
            y1 = max(py, y0 + minSize)
        case .top:
            y0 = min(py, y1 - minSize)
        case .bottom:
            y1 = max(py, y0 + minSize)
        case .left:
            x0 = min(px, x1 - minSize)
        case .right:
            x1 = max(px, x0 + minSize)
        }

        var next = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

        if let aspect = resolvedAspect(sourceSize: sourceSize) {
            // Rebuild from the moving handle while locking aspect.
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                var w = next.width
                var h = w / aspect
                if abs(next.height - h) > abs(next.width - next.height * aspect) {
                    h = next.height
                    w = h * aspect
                }
                switch handle {
                case .topLeft:
                    next = CGRect(x: x1 - w, y: y1 - h, width: w, height: h)
                case .topRight:
                    next = CGRect(x: x0, y: y1 - h, width: w, height: h)
                case .bottomLeft:
                    next = CGRect(x: x1 - w, y: y0, width: w, height: h)
                case .bottomRight:
                    next = CGRect(x: x0, y: y0, width: w, height: h)
                default:
                    break
                }
            case .top, .bottom:
                let h = next.height
                let w = h * aspect
                let x = r.midX - w / 2
                if handle == .top {
                    next = CGRect(x: x, y: y1 - h, width: w, height: h)
                } else {
                    next = CGRect(x: x, y: y0, width: w, height: h)
                }
            case .left, .right:
                let w = next.width
                let h = w / aspect
                let y = r.midY - h / 2
                if handle == .left {
                    next = CGRect(x: x1 - w, y: y, width: w, height: h)
                } else {
                    next = CGRect(x: x0, y: y, width: w, height: h)
                }
            }
        }

        // Clamp into source bounds without changing size when possible.
        next.size.width = max(minSize, min(next.width, sourceSize.width))
        next.size.height = max(minSize, min(next.height, sourceSize.height))
        next.origin.x = GeometryUtil.clamp(next.origin.x, min: 0, max: sourceSize.width - next.width)
        next.origin.y = GeometryUtil.clamp(next.origin.y, min: 0, max: sourceSize.height - next.height)
        setPixelRect(next, sourceSize: sourceSize, constrainAspect: false)
    }

    public func resolvedAspect(sourceSize: CGSize) -> CGFloat? {
        switch aspectLock {
        case .free: return nil
        case .matchSource:
            guard GeometryUtil.isValidSize(sourceSize) else { return nil }
            let aspect = sourceSize.width / sourceSize.height
            guard aspect.isFinite, aspect > 0 else { return nil }
            return aspect
        default:
            guard let aspect = aspectLock.aspect, aspect.isFinite, aspect > 0 else { return nil }
            return aspect
        }
    }

    /// Normalized rect with non-finite / empty values replaced by a full frame.
    private var sanitizedNormalizedRect: CGRect {
        let r = normalizedRect
        let components = [r.origin.x, r.origin.y, r.size.width, r.size.height]
        guard components.allSatisfy({ $0.isFinite }),
              r.size.width > 0, r.size.height > 0
        else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return r
    }

    private mutating func setNormalizedRect(from pixelRect: CGRect, sourceSize: CGSize) {
        guard GeometryUtil.isValidSize(sourceSize),
              pixelRect.origin.x.isFinite, pixelRect.origin.y.isFinite,
              pixelRect.size.width.isFinite, pixelRect.size.height.isFinite
        else {
            return
        }
        let next = CGRect(
            x: pixelRect.origin.x / sourceSize.width,
            y: pixelRect.origin.y / sourceSize.height,
            width: pixelRect.size.width / sourceSize.width,
            height: pixelRect.size.height / sourceSize.height
        )
        let components = [next.origin.x, next.origin.y, next.size.width, next.size.height]
        guard components.allSatisfy({ $0.isFinite }),
              next.size.width > 0, next.size.height > 0
        else {
            return
        }
        normalizedRect = next
    }

    private func alignRect(_ rect: CGRect, in bounds: CGSize, align: CropAlign) -> CGRect {
        var r = rect
        switch align {
        case .center:
            r.origin.x = CGFloat(GeometryUtil.safeInt((bounds.width - r.width) / 2))
            r.origin.y = CGFloat(GeometryUtil.safeInt((bounds.height - r.height) / 2))
        case .top:
            r.origin.y = 0
            r.origin.x = CGFloat(GeometryUtil.safeInt((bounds.width - r.width) / 2))
        case .bottom:
            r.origin.y = CGFloat(GeometryUtil.safeInt(bounds.height - r.height))
            r.origin.x = CGFloat(GeometryUtil.safeInt((bounds.width - r.width) / 2))
        case .left:
            r.origin.x = 0
            r.origin.y = CGFloat(GeometryUtil.safeInt((bounds.height - r.height) / 2))
        case .right:
            r.origin.x = CGFloat(GeometryUtil.safeInt(bounds.width - r.width))
            r.origin.y = CGFloat(GeometryUtil.safeInt((bounds.height - r.height) / 2))
        case .topLeft:
            r.origin = .zero
        case .topRight:
            r.origin.x = CGFloat(GeometryUtil.safeInt(bounds.width - r.width))
            r.origin.y = 0
        case .bottomLeft:
            r.origin.x = 0
            r.origin.y = CGFloat(GeometryUtil.safeInt(bounds.height - r.height))
        case .bottomRight:
            r.origin.x = CGFloat(GeometryUtil.safeInt(bounds.width - r.width))
            r.origin.y = CGFloat(GeometryUtil.safeInt(bounds.height - r.height))
        }
        r.origin.x = GeometryUtil.clamp(r.origin.x, min: 0, max: max(0, bounds.width - r.width))
        r.origin.y = GeometryUtil.clamp(r.origin.y, min: 0, max: max(0, bounds.height - r.height))
        return r
    }
}
