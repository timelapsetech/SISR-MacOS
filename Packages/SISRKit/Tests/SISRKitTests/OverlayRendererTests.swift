import CoreGraphics
import Foundation
import Testing
@testable import SISRKit

@Suite("OverlayRenderer")
struct OverlayRendererTests {
    @Test func burnInPlateMatchesGammaOpacityOverMidGray() throws {
        let width = 200
        let height = 120
        let opacity = 0.5

        let colorSpace = CGColorSpaceCreateDeviceRGB()
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
            Issue.record("Could not create gray canvas")
            return
        }
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let grayImage = ctx.makeImage() else {
            Issue.record("Could not make gray image")
            return
        }

        let burned = OverlayRenderer.burnIn(
            on: grayImage,
            overlay: .frame,
            text: "FRAME 01",
            backgroundOpacity: opacity
        )

        let layout = OverlayRenderer.layoutMetrics(
            overlay: .frame,
            text: "FRAME 01",
            canvasWidth: width,
            canvasHeight: height
        )
        let sample = try samplePixel(burned, at: CGPoint(x: layout.boxRect.midX, y: layout.boxRect.midY))

        // SwiftUI / CG gamma blend: mid-gray * (1 - 0.5) ≈ 0.25 → ~64
        // CI linear blend of the same opacity lands near ~92 and looks washed out.
        #expect(sample.r >= 58 && sample.r <= 70)
        #expect(sample.g >= 58 && sample.g <= 70)
        #expect(sample.b >= 58 && sample.b <= 70)
        // CI linear compositing of the same opacity lands near ~92 (washed out).
        #expect(sample.r < 85)
    }

    private struct RGBA {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }

    private func samplePixel(_ image: CGImage, at point: CGPoint) throws -> RGBA {
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
        ctx.translateBy(x: -point.x, y: -point.y)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return RGBA(r: pixel[0], g: pixel[1], b: pixel[2], a: pixel[3])
    }

    private enum SampleError: Error {
        case context
    }
}
