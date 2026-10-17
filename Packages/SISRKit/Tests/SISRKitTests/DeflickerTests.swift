import CoreGraphics
import Foundation
import Testing
@testable import SISRKit

@Suite("Deflicker")
struct DeflickerTests {
    // MARK: - Synthetic stats

    /// Quantiles spread linearly ±2·contrast stops around `brightness` (kept below white).
    private func stats(
        brightness: Double,
        contrast: Double = 1,
        chromaRG: Float = 0,
        chromaBG: Float = 0,
        grid: [Float]? = nil,
        cameraExposure: Double? = nil
    ) -> DeflickerFrameStats {
        let quantiles = DeflickerFrameStats.quantileLevels.map { p in
            Float(brightness + contrast * 4 * (p - 0.5))
        }
        let region = DeflickerRegionStats(quantiles: quantiles, chromaRG: chromaRG, chromaBG: chromaBG)
        let cells = DeflickerFrameStats.gridColumns * DeflickerFrameStats.gridRows
        return DeflickerFrameStats(
            regions: DeflickerMetering.allCases.map { _ in region },
            grid: grid ?? [Float](repeating: Float(brightness), count: cells),
            cameraExposure: cameraExposure
        )
    }

    private func settings(
        window: Int = 9,
        smoothing: DeflickerSmoothing = .gaussian,
        target: DeflickerTarget = .followScene,
        contrast: Bool = false,
        color: Bool = false,
        local: DeflickerLocalGrid = .off,
        camera: Bool = false
    ) -> DeflickerSettings {
        DeflickerSettings(
            enabled: true,
            windowSize: window,
            strength: 1,
            smoothing: smoothing,
            target: target,
            matchContrast: contrast,
            balanceColor: color,
            localGrid: local,
            useCameraExposure: camera,
            maxCorrectionEV: 3
        )
    }

    private func maxStep(_ x: [Double]) -> Double {
        zip(x.dropFirst(), x).map { abs($0 - $1) }.max() ?? 0
    }

    // MARK: - Settings

    @Test func legacySettingsDecodeWithDefaults() throws {
        let json = #"{"enabled":true,"windowSize":9,"strength":0.5}"#
        let decoded = try JSONDecoder().decode(DeflickerSettings.self, from: Data(json.utf8))
        #expect(decoded.enabled)
        #expect(decoded.windowSize == 9)
        #expect(decoded.strength == 0.5)
        #expect(decoded.smoothing == .robust)
        #expect(decoded.target == .followScene)
        #expect(decoded.localGrid == .off)

        var full = DeflickerPreset.sunAndClouds.settings(from: decoded)
        full.referenceFrame = 12
        let roundTrip = try JSONDecoder().decode(
            DeflickerSettings.self,
            from: JSONEncoder().encode(full)
        )
        #expect(roundTrip == full)
    }

    @Test func presetsRoundTripAndEditsBecomeCustom() {
        let base = DeflickerSettings(enabled: true)
        for preset in DeflickerPreset.tuned {
            #expect(DeflickerPreset.matching(preset.settings(from: base)) == preset)
        }
        var edited = DeflickerPreset.sunAndClouds.settings(from: base)
        edited.windowSize = 45
        #expect(DeflickerPreset.matching(edited) == .custom)
        #expect(DeflickerPreset.custom.settings(from: edited) == edited)
    }

    // MARK: - Solver

    @Test func alternatingFlickerIsCancelled() {
        let frames = (0..<40).map { stats(brightness: -3 + ($0 % 2 == 0 ? 0.5 : -0.5)) }
        for kind in DeflickerSmoothing.allCases {
            let solution = DeflickerSolver.solve(stats: frames, settings: settings(smoothing: kind))
            for (i, c) in solution.corrections.enumerated().dropFirst(4).dropLast(4) {
                let expected = i % 2 == 0 ? -0.5 : 0.5
                #expect(abs(c.exposureEV - expected) < 0.1, "\(kind) frame \(i): \(c.exposureEV)")
            }
            #expect(maxStep(solution.corrected) < 0.15, "\(kind)")
            #expect(maxStep(solution.measured) > 0.9)
        }
    }

    @Test func slowRampIsPreservedIncludingEnds() {
        let frames = (0..<60).map { stats(brightness: -1.5 - Double($0) * 0.05) }
        for kind in DeflickerSmoothing.allCases {
            let solution = DeflickerSolver.solve(stats: frames, settings: settings(window: 21, smoothing: kind))
            #expect(solution.maxAbsExposure < 0.05, "\(kind): \(solution.maxAbsExposure)")
        }
    }

    @Test func robustIgnoresSingleOutlierFrame() {
        var frames = (0..<30).map { _ in stats(brightness: -3) }
        frames[15] = stats(brightness: -1.5)
        let robust = DeflickerSolver.solve(stats: frames, settings: settings(smoothing: .robust))
        #expect(abs(robust.corrections[15].exposureEV + 1.5) < 0.05)
        #expect(abs(robust.corrections[14].exposureEV) < 0.01)
        #expect(abs(robust.corrections[16].exposureEV) < 0.01)

        // A plain average lets the outlier drag neighbors around.
        let average = DeflickerSolver.solve(stats: frames, settings: settings(smoothing: .average))
        #expect(abs(average.corrections[14].exposureEV) > 0.1)
    }

    @Test func lockedTargetMatchesReferenceFrame() {
        let levels: [Double] = [-2, -3.5, -2.8, -4, -3]
        let frames = levels.map { stats(brightness: $0) }
        let solution = DeflickerSolver.solve(
            stats: frames,
            settings: settings(target: .locked),
            referenceIndex: 2
        )
        for (level, c) in zip(levels, solution.corrections) {
            #expect(abs(level + c.exposureEV - -2.8) < 0.01)
        }
        let median = DeflickerSolver.solve(stats: frames, settings: settings(target: .locked))
        for (level, c) in zip(levels, median.corrections) {
            #expect(abs(level + c.exposureEV - -3) < 0.01)
        }
    }

    @Test func clippingRefinementBrightensFurther() {
        // Bright frame whose top quantiles sit at white: plain EV would undershoot.
        var bright = stats(brightness: -0.6, contrast: 0.6)
        bright.regions = bright.regions.map { r in
            var r = r
            r.quantiles = r.quantiles.map { min(0, $0) }
            return r
        }
        let dark = stats(brightness: -2.6, contrast: 0.6)
        let frames = [dark, dark, dark, dark, dark, dark, dark]
        var s = settings(target: .locked)
        s.maxCorrectionEV = 4
        let solution = DeflickerSolver.solve(stats: frames + [bright], settings: s, referenceIndex: 7)
        let reached = solution.corrected[0]
        let naive = solution.target[0] - solution.measured[0]
        #expect(abs(reached - solution.target[0]) < 0.02)
        #expect(solution.corrections[0].exposureEV > naive + 0.02)
    }

    @Test func cameraExposureStepsAreRemoved() {
        // Manual ramp: +1 stop of exposure every 20 frames; the scene darkens smoothly.
        let frames = (0..<80).map { i -> DeflickerFrameStats in
            let camera = Double(i / 20)
            let scene = -2 - Double(i) * 0.05
            return stats(brightness: scene + camera, cameraExposure: camera)
        }
        // Without EXIF the 1-stop jumps only get squeezed into the short window.
        let without = DeflickerSolver.solve(stats: frames, settings: settings(window: 9, smoothing: .robust))
        // With EXIF they are removed and re-spread over a long, gentle ramp.
        let with = DeflickerSolver.solve(
            stats: frames,
            settings: settings(window: 9, smoothing: .robust, camera: true)
        )
        #expect(maxStep(with.corrected) < 0.13)
        #expect(maxStep(with.corrected) < maxStep(without.corrected) * 0.7)
    }

    @Test func colorBalanceIsLuminanceNeutral() {
        let frames = (0..<20).map { i in
            stats(brightness: -3, chromaRG: i % 2 == 0 ? 0.2 : -0.2, chromaBG: i % 2 == 0 ? -0.2 : 0.2)
        }
        let solution = DeflickerSolver.solve(stats: frames, settings: settings(color: true))
        let c = solution.corrections[10]
        #expect(c.redGain < 1 && c.blueGain > 1)
        let luminance = 0.2126 * c.redGain + 0.7152 * c.greenGain + 0.0722 * c.blueGain
        #expect(abs(luminance - 1) < 1e-6)
    }

    @Test func contrastMatchBuildsMonotoneCurve() {
        let frames = (0..<20).map { stats(brightness: -3, contrast: $0 % 2 == 0 ? 1.4 : 0.6) }
        let solution = DeflickerSolver.solve(stats: frames, settings: settings(contrast: true))
        let hard = try? #require(solution.corrections[10].toneCurve)
        let flat = try? #require(solution.corrections[11].toneCurve)
        #expect(hard != nil && flat != nil)
        guard let hard, let flat else { return }

        let lut = hard.srgbLUT()
        #expect(lut.first == 0)
        #expect(lut.last == 1)
        #expect(zip(lut.dropFirst(), lut).allSatisfy { $0 >= $1 })

        // Hard-contrast frame: shadows lifted. Flat frame: shadows deepened.
        let shadowIndex = hard.anchors.count / 6
        #expect(hard.offsets[shadowIndex] > 0.1)
        #expect(flat.offsets[min(shadowIndex, flat.offsets.count - 1)] < -0.1)
        #expect(abs(solution.corrections[10].exposureEV) < 0.05)
    }

    @Test func localGridCountersRegionalShadow() {
        let cols = DeflickerFrameStats.gridColumns
        let rows = DeflickerFrameStats.gridRows
        let frames = (0..<20).map { i -> DeflickerFrameStats in
            // Left half dips 1 stop every other frame (a passing cloud shadow).
            let shadow: Float = i % 2 == 0 ? -1 : 0
            let grid = (0..<(cols * rows)).map { idx -> Float in
                idx % cols < cols / 2 ? -3 + shadow : -3
            }
            return stats(brightness: -3, grid: grid)
        }
        let solution = DeflickerSolver.solve(stats: frames, settings: settings(local: .coarse))
        let shaded = try? #require(solution.corrections[10].localGrid)
        #expect(shaded?.columns == 4 && shaded?.rows == 3)
        guard let shaded else { return }
        #expect(shaded.stops[0] > 0.2)
        #expect(shaded.stops[3] < -0.2)
    }

    // MARK: - Measurement

    @Test func statisticsGridIsTopRowFirst() {
        let w = 32
        let h = 24
        var px = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let v: Float = y < h / 3 ? 0.9 : 0.05
            for x in 0..<w {
                let i = (y * w + x) * 4
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 1
            }
        }
        let s = DeflickerAnalyzer.statistics(linearRGBA: px, width: w, height: h)
        #expect(s.grid[0] > s.grid[s.grid.count - 1] + 3)
        let full = DeflickerSolver.brightness(s.region(.fullFrame).quantiles.map(Double.init))
        let ground = DeflickerSolver.brightness(s.region(.ignoreSky).quantiles.map(Double.init))
        #expect(ground < full - 0.5)
    }

    @Test func gainGridBrightensTopOfFrame() throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-deflicker-grid")
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = try TestSupport.writeSolidSequence(
            directory: dir, frameCount: 1, width: 64, height: 64, red: 0.4, green: 0.4, blue: 0.4
        )
        let correction = DeflickerCorrection(
            localGrid: DeflickerGainGrid(columns: 1, rows: 2, stops: [1, 0])
        )
        let image = try #require(FramePipeline().renderCGImage(from: TestSupport.pipelineInput(
            imageURL: spec.frames[0].url,
            outputSize: PixelSize(width: 64, height: 64),
            deflicker: correction
        )))
        let top = try TestSupport.samplePixel(image, at: CGPoint(x: 32, y: 60))
        let bottom = try TestSupport.samplePixel(image, at: CGPoint(x: 32, y: 3))
        #expect(top.luma > bottom.luma + 0.15)
    }

    /// Real frames alternating sun / cloud brightness come out balanced after correction.
    @Test func endToEndBalancesRenderedFrames() async throws {
        let dir = try TestSupport.makeTempDir(prefix: "sisr-deflicker-e2e")
        defer { try? FileManager.default.removeItem(at: dir) }
        let width = 96
        let height = 64
        let levels: [CGFloat] = (0..<12).map { $0 % 2 == 0 ? 0.62 : 0.38 }
        let spec = try TestSupport.writeNumberedSequence(
            directory: dir, frameCount: levels.count, width: width, height: height
        ) { index, ctx, size in
            // Horizontal gradient so frames have a real tonal range.
            for x in 0..<Int(size.width) {
                let v = levels[index] * (0.6 + 0.8 * CGFloat(x) / size.width)
                ctx.setFillColor(red: min(1, v), green: min(1, v), blue: min(1, v), alpha: 1)
                ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: size.height))
            }
        }
        let output = PixelSize(width: width, height: height)
        let urls = spec.frames.map(\.url)
        let stats = try await DeflickerAnalyzer().analyze(
            urls: urls,
            crop: .fullFrame,
            adjustments: .identity,
            outputSize: output
        )
        let solution = DeflickerSolver.solve(
            stats: stats,
            settings: DeflickerPreset.standard.settings(from: DeflickerSettings(enabled: true))
        )

        let pipeline = FramePipeline()
        func lumas(_ corrections: [DeflickerCorrection]) throws -> [Double] {
            try urls.enumerated().map { i, url in
                let cg = try #require(pipeline.renderCGImage(from: TestSupport.pipelineInput(
                    imageURL: url, outputSize: output, deflicker: corrections[i]
                )))
                return try TestSupport.sampleCenter(cg).luma
            }
        }
        let before = try lumas(Array(repeating: .identity, count: urls.count))
        let after = try lumas(solution.corrections)
        let swingBefore = maxStep(Array(before[2..<10]))
        let swingAfter = maxStep(Array(after[2..<10]))
        #expect(swingBefore > 0.15)
        #expect(swingAfter < swingBefore * 0.2, "before \(swingBefore) after \(swingAfter)")
    }

    @Test func renderReusesMatchingAnalysis() async throws {
        let root = try TestSupport.makeTempDir(prefix: "sisr-deflicker-cache")
        defer { try? FileManager.default.removeItem(at: root) }
        let sequenceDir = root.appendingPathComponent("seq", isDirectory: true)
        let outputDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: sequenceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let spec = try TestSupport.writeSolidSequence(
            directory: sequenceDir, frameCount: 4, width: 64, height: 36, red: 0.4, green: 0.4, blue: 0.4
        )
        let output = PixelSize(width: 64, height: 36)
        var snapshot = TestSupport.renderSnapshot(
            sequence: spec,
            sourceSize: CGSize(width: 64, height: 36),
            outputSize: output,
            codec: .h264,
            outputDirectory: outputDir,
            adjustments: Adjustments(deflicker: DeflickerSettings(enabled: true)),
            outputBaseName: "cached"
        )
        let key = try #require(DeflickerAnalysisKey(project: snapshot))
        snapshot.deflickerAnalysis = DeflickerAnalysis(
            key: key,
            startIndex: 0,
            stats: Array(repeating: DeflickerAnalyzer.neutralStats, count: 4)
        )

        let probe = TestSupport.ProgressProbe()
        _ = try await Renderer().render(project: snapshot, progress: probe.handler)
        #expect(probe.finished)
        #expect(!probe.sawDeflicker)
    }
}
