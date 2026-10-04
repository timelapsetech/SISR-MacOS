import CoreGraphics
import Foundation

/// Straighten helpers: rotate around the crop center and zoom only when needed
/// so the crop window never samples outside the source (no black padding).
public enum StraightenGeometry {
    /// Scale ≥ 1 applied to the image about the crop center. `1` means no zoom.
    public static func coverScale(
        sourceSize: CGSize,
        cropRect: CGRect,
        degrees: Double
    ) -> CGFloat {
        guard abs(degrees) >= 0.001,
              sourceSize.width > 0,
              sourceSize.height > 0,
              cropRect.width > 0,
              cropRect.height > 0
        else {
            return 1
        }

        let radians = degrees * .pi / 180
        let center = CGPoint(x: cropRect.midX, y: cropRect.midY)
        let halfW = cropRect.width / 2
        let halfH = cropRect.height / 2

        // Corners + edge midpoints of the fixed crop window.
        let samples: [CGPoint] = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: -halfW, y: halfH),
            CGPoint(x: halfW, y: halfH),
            CGPoint(x: 0, y: -halfH),
            CGPoint(x: 0, y: halfH),
            CGPoint(x: -halfW, y: 0),
            CGPoint(x: halfW, y: 0),
        ]

        func fits(_ scale: CGFloat) -> Bool {
            // Image is rotated by +θ about C (matches SwiftUI preview direction under
            // Core Image’s Y-up convention). Fixed crop point P therefore samples:
            // C + R(-θ) * ((P - C) / scale)
            let cosA = Foundation.cos(-radians)
            let sinA = Foundation.sin(-radians)
            for rel in samples {
                let x = rel.x / scale
                let y = rel.y / scale
                let sx = center.x + x * cosA - y * sinA
                let sy = center.y + x * sinA + y * cosA
                if sx < -0.5 || sy < -0.5
                    || sx > sourceSize.width + 0.5
                    || sy > sourceSize.height + 0.5
                {
                    return false
                }
            }
            return true
        }

        if fits(1) { return 1 }

        var lo: CGFloat = 1
        var hi: CGFloat = 1
        // Expand upper bound until it fits (or cap).
        while hi < 32, !fits(hi) {
            hi *= 1.5
        }
        if !fits(hi) { return hi }

        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if fits(mid) {
                hi = mid
            } else {
                lo = mid
            }
        }
        return hi
    }
}
