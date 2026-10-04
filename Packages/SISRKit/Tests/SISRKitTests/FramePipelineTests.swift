import CoreGraphics
import Foundation
import Testing
@testable import SISRKit

@Suite("FramePipeline")
struct FramePipelineTests {
    @Test func outputSizeMatchesRequested() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-size")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: 640,
            height: 360,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let output = PixelSize(width: 320, height: 180)
        let input = TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output
        )
        let cg = try #require(FramePipeline().renderCGImage(from: input))
        #expect(cg.width == output.width)
        #expect(cg.height == output.height)
    }

    @Test func cropSelectsLeftVersusRightRegion() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-crop")
        defer { try? FileManager.default.removeItem(at: dir) }

        let width = 200
        let height = 100
        let split = try TestSupport.makeSplitHorizontalImage(
            width: width,
            height: height,
            left: (1, 0, 0),
            right: (0, 0, 1)
        )
        let url = dir.appendingPathComponent("clip_0001.png")
        try TestSupport.writePNG(split, to: url)
        // Second frame required only if we used a sequence; pipeline takes a single URL.
        let url2 = dir.appendingPathComponent("clip_0002.png")
        try TestSupport.writePNG(split, to: url2)

        let leftCrop = CropState(
            normalizedRect: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        )
        let rightCrop = CropState(
            normalizedRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        )
        let out = PixelSize(width: 100, height: 100)
        let pipeline = FramePipeline()

        let left = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: url,
            outputSize: out,
            crop: leftCrop
        )))
        let right = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: url,
            outputSize: out,
            crop: rightCrop
        )))

        let leftSample = try TestSupport.sampleCenter(left)
        let rightSample = try TestSupport.sampleCenter(right)
        #expect(leftSample.r > 200)
        #expect(leftSample.b < 40)
        #expect(rightSample.b > 200)
        #expect(rightSample.r < 40)
    }

    @Test func quarterTurnSwapsOutputDimensionsForOriginalSize() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-rot")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: 200,
            height: 100,
            red: 0.4,
            green: 0.4,
            blue: 0.4
        )
        var crop = CropState.fullFrame
        crop.setQuarterTurns(1)
        // Oriented source is 100×200; original output follows crop pixels.
        let oriented = crop.orientedSize(of: CGSize(width: 200, height: 100))
        let output = PixelSize(width: Int(oriented.width), height: Int(oriented.height)).even
        let cg = try #require(FramePipeline().renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            crop: crop
        )))
        #expect(cg.width == 100)
        #expect(cg.height == 200)
    }

    @Test func overlayPlateDarkensAtHalfOpacity() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-overlay")
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 320
        let height = 180
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: width,
            height: height,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let output = PixelSize(width: width, height: height)
        let text = "FRAME 01"
        let pipeline = FramePipeline()

        let none = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .none
        )))
        let burned = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 0.5
        )))

        let layout = OverlayRenderer.layoutMetrics(
            overlay: .frame,
            text: text,
            canvasWidth: width,
            canvasHeight: height
        )
        // Sample plate padding (avoid glyph ink).
        let platePoint = CGPoint(
            x: layout.boxRect.minX + layout.padding * 0.5,
            y: layout.boxRect.minY + layout.padding * 0.5
        )
        let clearPoint = CGPoint(x: 16, y: 16)

        let nonePlate = try TestSupport.samplePixel(none, at: platePoint)
        let burnedPlate = try TestSupport.samplePixel(burned, at: platePoint)
        let burnedClear = try TestSupport.samplePixel(burned, at: clearPoint)

        #expect(burnedPlate.luma < nonePlate.luma - 0.1)
        #expect(abs(burnedClear.luma - nonePlate.luma) < 0.05)
        #expect(burnedPlate.r >= 50 && burnedPlate.r <= 80)
    }

    @Test func overlayOpacityExtremes() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-opacity")
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 320
        let height = 180
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: width,
            height: height,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let output = PixelSize(width: width, height: height)
        let text = "FRAME 01"
        let layout = OverlayRenderer.layoutMetrics(
            overlay: .frame,
            text: text,
            canvasWidth: width,
            canvasHeight: height
        )
        let platePoint = CGPoint(
            x: layout.boxRect.minX + layout.padding * 0.5,
            y: layout.boxRect.minY + layout.padding * 0.5
        )
        let pipeline = FramePipeline()

        let zero = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 0
        )))
        let full = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 1
        )))
        let base = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output
        )))

        let zeroSample = try TestSupport.samplePixel(zero, at: platePoint)
        let fullSample = try TestSupport.samplePixel(full, at: platePoint)
        let baseSample = try TestSupport.samplePixel(base, at: platePoint)

        #expect(abs(zeroSample.luma - baseSample.luma) < 0.08)
        #expect(fullSample.r < 20)
        #expect(fullSample.g < 20)
        #expect(fullSample.b < 20)
    }

    @Test func dateOverlayBakesPlate() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-date")
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 320
        let height = 180
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: width,
            height: height,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let text = DateOverlayFormatter.format("2024:01:05 13:30:00")
        #expect(!text.isEmpty)
        let output = PixelSize(width: width, height: height)
        let burned = try #require(FramePipeline().renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .date,
            overlayText: text,
            overlayBackgroundOpacity: 0.5
        )))
        let layout = OverlayRenderer.layoutMetrics(
            overlay: .date,
            text: text,
            canvasWidth: width,
            canvasHeight: height
        )
        let platePoint = CGPoint(
            x: layout.boxRect.minX + layout.padding * 0.5,
            y: layout.boxRect.minY + layout.padding * 0.5
        )
        let sample = try TestSupport.samplePixel(burned, at: platePoint)
        #expect(sample.r < 100)
        #expect(sample.luma < 0.35)
    }

    @Test func exposureBiasBrightensFrame() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-grade")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: 160,
            height: 90,
            red: 0.4,
            green: 0.4,
            blue: 0.4
        )
        let output = PixelSize(width: 160, height: 90)
        let pipeline = FramePipeline()
        let identity = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output
        )))
        let boosted = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            adjustments: Adjustments(color: ColorAdjustments(exposure: 1.0)),
            exposureBias: 0.5
        )))
        let a = try TestSupport.sampleCenter(identity)
        let b = try TestSupport.sampleCenter(boosted)
        #expect(b.luma > a.luma + 0.1)
    }

    @Test func compositionPreviewAndShowOriginalSkipOverlay() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-pipe-preview")
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 200
        let height = 120
        let spec = try TestSupport.writeSolidSequence(
            directory: dir,
            frameCount: 2,
            width: width,
            height: height,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let text = "FRAME 01"
        let output = PixelSize(width: width, height: height)
        let layout = OverlayRenderer.layoutMetrics(
            overlay: .frame,
            text: text,
            canvasWidth: width,
            canvasHeight: height
        )
        let platePoint = CGPoint(
            x: layout.boxRect.minX + layout.padding * 0.5,
            y: layout.boxRect.minY + layout.padding * 0.5
        )
        let pipeline = FramePipeline()

        let preview = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 1,
            compositionPreview: true
        )))
        let original = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 1,
            showOriginal: true
        )))
        let baked = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: output,
            overlay: .frame,
            overlayText: text,
            overlayBackgroundOpacity: 1
        )))

        let previewSample = try TestSupport.samplePixel(preview, at: platePoint)
        let originalSample = try TestSupport.samplePixel(original, at: platePoint)
        let bakedSample = try TestSupport.samplePixel(baked, at: platePoint)

        #expect(previewSample.luma > 0.35)
        #expect(originalSample.luma > 0.35)
        #expect(bakedSample.r < 20)
    }
}
