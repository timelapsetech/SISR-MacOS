import CoreGraphics
import Foundation
import Testing
@testable import SISRKit

@Suite("RenderSmoke")
struct RenderSmokeTests {
    private let frameWidth = 320
    private let frameHeight = 180

    @Test(arguments: OutputCodec.allCases)
    func encodesTinySequence(codec: OutputCodec) async throws {
        let root = try TestSupport.makeTempDir(prefix: "sisr-smoke-\(codec.rawValue)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sequenceDir = root.appendingPathComponent("seq", isDirectory: true)
        let outputDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: sequenceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let spec = try TestSupport.writeSolidSequence(
            directory: sequenceDir,
            frameCount: 3,
            width: frameWidth,
            height: frameHeight,
            red: 0.35,
            green: 0.4,
            blue: 0.45,
            prefix: "clip"
        )
        let outputSize = PixelSize(width: frameWidth, height: frameHeight)
        let snapshot = TestSupport.renderSnapshot(
            sequence: spec,
            sourceSize: CGSize(width: frameWidth, height: frameHeight),
            outputSize: outputSize,
            codec: codec,
            outputDirectory: outputDir,
            outputBaseName: "smoke_\(codec.rawValue)"
        )

        let probe = TestSupport.ProgressProbe()
        let url = try await Renderer().render(project: snapshot, progress: probe.handler)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension.lowercased() == codec.fileExtension)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        // Tiny GIFs can be under 500 bytes; video containers are larger.
        let minimum: Int64 = codec == .gif ? 200 : 500
        #expect(size > minimum)
        #expect(probe.finished)
    }

    @Test func h264DateOverlayRespectsInOutRange() async throws {
        let root = try TestSupport.makeTempDir(prefix: "sisr-smoke-inout")
        defer { try? FileManager.default.removeItem(at: root) }
        let sequenceDir = root.appendingPathComponent("seq", isDirectory: true)
        let outputDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: sequenceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let spec = try TestSupport.writeSolidSequence(
            directory: sequenceDir,
            frameCount: 3,
            width: frameWidth,
            height: frameHeight,
            red: 0.5,
            green: 0.5,
            blue: 0.5
        )
        let dates = [
            "2024:01:05 13:30:00",
            "2024:01:05 13:30:01",
            "2024:01:05 13:30:02",
        ]
        let outputSize = PixelSize(width: frameWidth, height: frameHeight)
        let snapshot = TestSupport.renderSnapshot(
            sequence: spec,
            sourceSize: CGSize(width: frameWidth, height: frameHeight),
            outputSize: outputSize,
            codec: .h264,
            outputDirectory: outputDir,
            overlay: .date,
            timeline: TimelineRange(inIndex: 1, outIndex: 2),
            frameDates: dates,
            outputBaseName: "smoke_inout"
        )

        let probe = TestSupport.ProgressProbe()
        let url = try await Renderer().render(project: snapshot, progress: probe.handler)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent.contains("date"))
        #expect(probe.maxTotal == 2)
        #expect(probe.finishedTotal == 2)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        #expect(size > 500)
    }

    @Test func deflickerEnabledRenderCompletes() async throws {
        let root = try TestSupport.makeTempDir(prefix: "sisr-smoke-deflicker")
        defer { try? FileManager.default.removeItem(at: root) }
        let sequenceDir = root.appendingPathComponent("seq", isDirectory: true)
        let outputDir = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: sequenceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Varying luminance so deflicker analysis has signal.
        let luminances: [CGFloat] = [0.25, 0.55, 0.35]
        let spec = try TestSupport.writeNumberedSequence(
            directory: sequenceDir,
            frameCount: luminances.count,
            width: frameWidth,
            height: frameHeight
        ) { index, ctx, size in
            let y = luminances[index]
            ctx.setFillColor(red: y, green: y, blue: y, alpha: 1)
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        let outputSize = PixelSize(width: frameWidth, height: frameHeight)
        let snapshot = TestSupport.renderSnapshot(
            sequence: spec,
            sourceSize: CGSize(width: frameWidth, height: frameHeight),
            outputSize: outputSize,
            codec: .h264,
            outputDirectory: outputDir,
            adjustments: Adjustments(
                deflicker: DeflickerSettings(enabled: true, windowSize: 3, strength: 0.8)
            ),
            outputBaseName: "smoke_deflicker"
        )

        let probe = TestSupport.ProgressProbe()
        let url = try await Renderer().render(project: snapshot, progress: probe.handler)

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(probe.sawDeflicker)
        #expect(probe.finished)
    }
}
