import Foundation
import Testing
@testable import SISRKit

@Suite("SequenceScanner")
struct SequenceScannerTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sisr-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ dir: URL, names: [String]) throws -> [(URL, String?)] {
        try names.map { name in
            let url = dir.appendingPathComponent(name)
            try Data([0]).write(to: url)
            return (url, nil)
        }
    }

    @Test func resolveUnderscoreSequence() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["test_000.jpg", "test_001.jpg", "test_002.jpg"]
        let files = try touch(dir, names: names)
        let spec = try SequenceScanner.resolve(files, directory: dir)
        #expect(spec.numberWidth == 3)
        #expect(spec.pattern == "test_%03d.jpg")
        #expect(spec.frames.map(\.url.lastPathComponent) == names)
    }

    @Test func resolveSequenceStartingAtOne() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try touch(dir, names: ["img_0001.png", "img_0002.png", "img_0003.png"])
        let spec = try SequenceScanner.resolve(files, directory: dir)
        #expect(spec.startNumber == 1)
        #expect(spec.pattern == "img_%04d.png")
    }

    @Test func resolveNumberedWithoutUnderscore() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try touch(dir, names: ["DSCF0001.JPG", "DSCF0002.JPG"])
        let spec = try SequenceScanner.resolve(files, directory: dir)
        #expect(spec.startNumber == 1)
        #expect(spec.pattern == "DSCF%04d.JPG")
    }

    @Test func rejectsUnnumbered() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try touch(dir, names: ["photo.jpg", "screenshot.png"])
        #expect(throws: UnprocessableImageSequenceError.self) {
            try SequenceScanner.resolve(files, directory: dir)
        }
    }

    @Test func rejectsSingleImage() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try touch(dir, names: ["img_0001.jpg"])
        do {
            _ = try SequenceScanner.resolve(files, directory: dir)
            Issue.record("Expected throw")
        } catch let error as UnprocessableImageSequenceError {
            #expect(error.message.contains("at least 2"))
        }
    }

    @Test func rejectsGappySequence() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try touch(dir, names: ["img_001.jpg", "img_003.jpg"])
        do {
            _ = try SequenceScanner.resolve(files, directory: dir)
            Issue.record("Expected throw")
        } catch let error as UnprocessableImageSequenceError {
            #expect(error.message.contains("not consecutive"))
        }
    }
}
