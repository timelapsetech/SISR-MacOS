import CoreGraphics
import Foundation
import Testing
@testable import SISRKit

@Suite("Models")
struct ModelTests {
    @Test func evenDimensions() {
        #expect(GeometryUtil.even(1921) == 1920)
        #expect(GeometryUtil.even(1080) == 1080)
    }

    @Test func outputNaming() {
        var settings = RenderSettings(preset: .p1080, codec: .prores, overlay: .date, outputBaseName: "clip")
        let name = OutputNaming.makeFilename(
            baseName: "clip",
            settings: settings,
            cropLabel: "p1080",
            outputSize: PixelSize(width: 1920, height: 1080)
        )
        #expect(name == "clip_p1080_date_prores.mov")

        settings.codec = .h264
        settings.overlay = .none
        let name2 = OutputNaming.makeFilename(
            baseName: "clip",
            settings: settings,
            cropLabel: nil,
            outputSize: nil
        )
        #expect(name2.hasSuffix(".mp4"))
    }

    @Test func resolutionCheckNative() {
        let crop = PixelSize(width: 4000, height: 2250)
        let check = ResolutionCheck.evaluate(crop: crop, preset: .p1080)
        #expect(check?.fitness == .native)
    }

    @Test func resolutionCheckUpscaled() {
        let crop = PixelSize(width: 1600, height: 900)
        let check = ResolutionCheck.evaluate(crop: crop, preset: .p1080)
        #expect(check?.fitness == .upscaled)
        #expect(check?.willUpscale == true)
    }

    @Test func heavyUpscaleStillAllowed() {
        let crop = PixelSize(width: 640, height: 360)
        let check = ResolutionCheck.evaluate(crop: crop, preset: .uhd8k)
        #expect(check?.fitness == .tooSmall)
        #expect(check?.willUpscale == true)
        #expect(check?.badgeLabel.contains("Heavy upscale") == true)
    }

    @Test func cropAspectLock() {
        var crop = CropState.fullFrame
        let size = CGSize(width: 6000, height: 4000)
        crop.setAspectLock(.ratio16x9, sourceSize: size)
        let px = crop.pixelSize(sourceSize: size)
        let aspect = Double(px.width) / Double(px.height)
        #expect(abs(aspect - 16.0 / 9.0) < 0.02)
        #expect(px.width % 2 == 0)
        #expect(px.height % 2 == 0)
    }

    @Test func overlayBackgroundOpacityDefaultsAndClamps() {
        let settings = RenderSettings()
        #expect(settings.overlayBackgroundOpacity == 0.5)
        #expect(RenderSettings.clampOpacity(-1) == 0)
        #expect(RenderSettings.clampOpacity(2) == 1)
        let origin = OverlayRenderer.boxOrigin(
            overlay: .date,
            canvas: CGSize(width: 1000, height: 1000),
            boxSize: CGSize(width: 100, height: 40)
        )
        #expect(abs(origin.x - 850) < 0.5) // 1000 - 100 - 50 margin
        #expect(abs(origin.y - 50) < 0.5)
    }

    @Test func cropQuarterTurnsNormalize() {
        var crop = CropState.fullFrame
        crop.setQuarterTurns(2)
        #expect(crop.rotationDegrees == 180)
        crop.rotateRight()
        #expect(crop.rotationDegrees == 270)
        crop.rotateRight()
        #expect(crop.rotationDegrees == 0)
        crop.setQuarterTurns(-1)
        #expect(crop.rotationDegrees == 270)
    }

    @Test func orientedSourceSizeSwapsOnOddTurns() {
        let project = SequenceProject()
        project.sourceSize = CGSize(width: 6000, height: 4000)
        #expect(project.orientedSourceSize == CGSize(width: 6000, height: 4000))
        project.crop.setQuarterTurns(1)
        #expect(project.orientedSourceSize == CGSize(width: 4000, height: 6000))
        #expect(project.cropPixelSize == PixelSize(width: 4000, height: 6000))
        project.crop.setQuarterTurns(2)
        #expect(project.orientedSourceSize == CGSize(width: 6000, height: 4000))
    }

    @Test func cropPixelSizeSurvivesZeroSourceAndNaNRect() {
        var crop = CropState.fullFrame
        // Switching aspect before a sequence is loaded used to write NaN via 0/0.
        crop.setAspectLock(.ratio16x9, sourceSize: .zero)
        #expect(crop.normalizedRect == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(crop.pixelSize(sourceSize: .zero) == PixelSize(width: 0, height: 0))

        crop.normalizedRect = CGRect(x: CGFloat.nan, y: CGFloat.nan, width: CGFloat.infinity, height: CGFloat.nan)
        let size = CGSize(width: 1920, height: 1080)
        let px = crop.pixelSize(sourceSize: size)
        #expect(px.width == 1920)
        #expect(px.height == 1080)
        #expect(GeometryUtil.evenSize(CGSize(width: CGFloat.nan, height: CGFloat.infinity)) == .zero)
    }

    @Test func renderSettingsOutputSize() {
        let settings = RenderSettings(preset: .uhd4k)
        let out = settings.outputPixelSize(cropSize: PixelSize(width: 5000, height: 3000))
        #expect(out.width == 3840)
        #expect(out.height == 2160)
    }

    @Test func nativeOutputUsesCropPixels() {
        let settings = RenderSettings(preset: .original)
        let crop = PixelSize(width: 6000, height: 4000)
        let out = settings.outputPixelSize(cropSize: crop)
        #expect(out == crop.even)
    }

    @Test func scaleToFitDoesNotUpscaleOrCropAspect() {
        var settings = RenderSettings(preset: .fitWithin, maxWidth: 1920, maxHeight: nil)
        let crop = PixelSize(width: 6000, height: 4000)
        let out = settings.outputPixelSize(cropSize: crop)
        #expect(out.width == 1920)
        #expect(out.height == 1280)
        // Ceiling larger than source → stay at native (no upscale).
        settings.maxWidth = 8000
        let out2 = settings.outputPixelSize(cropSize: crop)
        #expect(out2.width == 6000)
        #expect(out2.height == 4000)
    }

    @Test func applyNativeFullFrameResetsCrop() {
        let project = SequenceProject()
        project.sourceSize = CGSize(width: 6000, height: 4000)
        project.crop.setAspectLock(.ratio16x9, sourceSize: project.sourceSize)
        project.crop.straightenDegrees = 5
        project.applyNativeFullFrameOutput()
        #expect(project.render.preset == .original)
        #expect(project.crop.aspectLock == .matchSource)
        #expect(project.crop.straightenDegrees == 0)
        let px = project.cropPixelSize
        #expect(px.width == 6000)
        #expect(px.height == 4000)
        #expect(project.outputPixelSize == px)
    }

    @Test func applyScaledFullFrame() {
        let project = SequenceProject()
        project.sourceSize = CGSize(width: 6000, height: 4000)
        project.applyScaledFullFrame(maxWidth: 1920, maxHeight: nil)
        #expect(project.render.preset == .fitWithin)
        #expect(project.render.maxWidth == 1920)
        #expect(project.outputPixelSize.width == 1920)
        #expect(project.outputPixelSize.height == 1280)
    }

    @Test func loadDoesNotDefaultOutputToSequenceFolder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sisr-out-default-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 1...2 {
            let name = String(format: "clip_%04d.jpg", i)
            // Minimal valid JPEG so ImageIO/size probing can succeed or fail gracefully.
            let url = dir.appendingPathComponent(name)
            try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        }
        let project = SequenceProject()
        project.render.outputDirectoryPath = dir.path // legacy default
        try project.load(directory: dir)
        #expect(project.render.outputDirectoryPath == nil)
        #expect(!project.hasOutputDirectory)
    }

    @Test func h264BitrateLadder() {
        #expect(VideoBitrate.h264BitsPerSecond(width: 1920, height: 1080) == 10_000_000)
        #expect(VideoBitrate.h264BitsPerSecond(width: 1080, height: 1920) == 10_000_000)
        #expect(VideoBitrate.h264BitsPerSecond(width: 3840, height: 2160) == 15_000_000)
        #expect(VideoBitrate.h264BitsPerSecond(width: 1280, height: 720) == 5_000_000)
        #expect(VideoBitrate.hevcBitsPerSecond(width: 1920, height: 1080) < 10_000_000)
    }

    @Test func videoEncodeOverrides() {
        var encode = VideoEncodeSettings.automatic
        #expect(encode.usesAutomaticDefaults)
        #expect(
            encode.resolvedAverageMbps(codec: .h264, width: 1920, height: 1080) == 10
        )
        encode.averageBitRateMbps = 20
        encode.maxBitRateMbps = 30
        encode.quality = 0.9
        #expect(!encode.usesAutomaticDefaults)
        #expect(encode.resolvedAverageBitsPerSecond(codec: .h264, width: 1920, height: 1080) == 20_000_000)
        #expect(encode.resolvedMaxBitsPerSecond(codec: .h264, width: 1920, height: 1080) == 30_000_000)
        #expect(encode.resolvedQuality == 0.9)
        encode.resetToDefaults()
        #expect(encode.usesAutomaticDefaults)
    }

    @Test func straightenCoverScaleCenterNeedsNoZoom() {
        let source = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 300, y: 300, width: 400, height: 400)
        let scale = StraightenGeometry.coverScale(sourceSize: source, cropRect: crop, degrees: 5)
        #expect(abs(scale - 1) < 0.001)
    }

    @Test func straightenCoverScaleNearEdgeZooms() {
        let source = CGSize(width: 1000, height: 1000)
        let crop = CGRect(x: 0, y: 0, width: 400, height: 400)
        let scale = StraightenGeometry.coverScale(sourceSize: source, cropRect: crop, degrees: 15)
        #expect(scale > 1.01)
    }
}
