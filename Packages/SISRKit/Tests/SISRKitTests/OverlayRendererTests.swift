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
        let sample = try TestSupport.samplePixel(
            burned,
            at: CGPoint(x: layout.boxRect.midX, y: layout.boxRect.midY)
        )

        // SwiftUI / CG gamma blend: mid-gray * (1 - 0.5) ≈ 0.25 → ~64
        // CI linear blend of the same opacity lands near ~92 and looks washed out.
        #expect(sample.r >= 58 && sample.r <= 70)
        #expect(sample.g >= 58 && sample.g <= 70)
        #expect(sample.b >= 58 && sample.b <= 70)
        // CI linear compositing of the same opacity lands near ~92 (washed out).
        #expect(sample.r < 85)
    }

    @Test func frameOverlayTextUsesAbsoluteSequenceIndex() {
        let text = OverlayRenderer.frameOverlayText(
            sequenceIndex: 49,
            sourceFrameNumber: 1050,
            mode: .countFromStart,
            pad: 4,
            totalFrames: 100
        )
        #expect(text == "FRAME 0050")

        let source = OverlayRenderer.frameOverlayText(
            sequenceIndex: 49,
            sourceFrameNumber: 1050,
            mode: .useSourceNumbers,
            pad: 4,
            totalFrames: 100
        )
        #expect(source == "FRAME 1050")
    }

    @Test func previewOverlayTextIgnoresInPoint() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-overlay-abs")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 20,
            width: 16,
            height: 16,
            red: 0.2,
            green: 0.2,
            blue: 0.2
        )
        let project = SequenceProject()
        project.sequence = spec
        project.timeline = TimelineRange(inIndex: 10, outIndex: 19)
        project.playheadIndex = 14
        project.render.overlay = .frame
        project.render.frameNumberMode = .countFromStart

        #expect(project.previewOverlayText(at: 14) == "FRAME 0015")
        #expect(project.previewOverlayText(at: 10) == "FRAME 0011")
        #expect(project.previewOverlayText(at: 0) == "FRAME 0001")
    }

    @Test func frameNumberModeDecodesLegacyInPointRawValue() throws {
        let data = Data(#""countFromInPoint""#.utf8)
        let mode = try JSONDecoder().decode(FrameNumberMode.self, from: data)
        #expect(mode == .countFromStart)
    }
}
