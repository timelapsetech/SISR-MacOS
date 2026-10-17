import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

extension FramePipeline {
    /// Exposure + channel gains (linear), regional gain map (linear), then tone curve (sRGB).
    func applyDeflicker(_ image: CIImage, correction: DeflickerCorrection, includeLocal: Bool) -> CIImage {
        guard !correction.isIdentity else { return image }
        var img = image
        let extent = image.extent

        let gain = exp2(correction.exposureEV)
        let r = gain * correction.redGain
        let g = gain * correction.greenGain
        let b = gain * correction.blueGain
        if abs(r - 1) > 1e-4 || abs(g - 1) > 1e-4 || abs(b - 1) > 1e-4 {
            let f = CIFilter.colorMatrix()
            f.inputImage = img
            f.rVector = CIVector(x: CGFloat(r), y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: CGFloat(g), z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: CGFloat(b), w: 0)
            f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            img = f.outputImage ?? img
        }

        if includeLocal, let grid = correction.localGrid, let map = gainMap(grid, extent: extent) {
            let f = CIFilter.multiplyCompositing()
            f.inputImage = map
            f.backgroundImage = img
            img = f.outputImage?.cropped(to: extent) ?? img
        }

        if let curve = correction.toneCurve {
            let lut = curve.srgbLUT()
            var triples = [Float]()
            triples.reserveCapacity(lut.count * 3)
            for v in lut {
                triples.append(v)
                triples.append(v)
                triples.append(v)
            }
            let f = CIFilter.colorCurves()
            f.inputImage = img
            f.curvesData = triples.withUnsafeBufferPointer { Data(buffer: $0) }
            f.curvesDomain = CIVector(x: 0, y: 1)
            if let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
                f.colorSpace = srgb
            }
            img = f.outputImage?.cropped(to: extent) ?? img
        }
        return img
    }

    /// Cell-centered gain grid stretched bilinearly over `extent`.
    private func gainMap(_ grid: DeflickerGainGrid, extent: CGRect) -> CIImage? {
        guard grid.columns > 0, grid.rows > 0, grid.stops.count == grid.columns * grid.rows,
              extent.width > 0, extent.height > 0
        else { return nil }
        var pixels = [Float]()
        pixels.reserveCapacity(grid.stops.count * 4)
        for stop in grid.stops {
            let gain = exp2(stop)
            pixels.append(gain)
            pixels.append(gain)
            pixels.append(gain)
            pixels.append(1)
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        // Bitmap row 0 is the top row, matching the analysis grid.
        let small = CIImage(
            bitmapData: data,
            bytesPerRow: grid.columns * 16,
            size: CGSize(width: grid.columns, height: grid.rows),
            format: .RGBAf,
            colorSpace: nil
        )
        let sx = extent.width / CGFloat(grid.columns)
        let sy = extent.height / CGFloat(grid.rows)
        return small.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }
}
