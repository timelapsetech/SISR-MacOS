import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFWriter {
    /// Incremental GIF writer — does not retain every frame in memory.
    public final class Stream {
        private let url: URL
        private let destination: CGImageDestination
        private let frameProps: CFDictionary
        private var added = 0
        private let expectedCount: Int

        public private(set) var resolvedURL: URL

        public init(url: URL, fps: Double, frameCount: Int) throws {
            let writable = try OutputFile.prepareWritableURL(url)
            self.url = writable
            self.resolvedURL = writable
            self.expectedCount = max(1, frameCount)

            guard let dest = CGImageDestinationCreateWithURL(
                writable as CFURL,
                UTType.gif.identifier as CFString,
                expectedCount,
                nil
            ) else {
                throw RenderError.writerFailed("Could not create GIF destination.")
            }
            destination = dest

            let delay = max(0.02, 1.0 / max(fps, 0.01))
            frameProps = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                ],
            ] as CFDictionary

            let gifProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0,
                ],
            ]
            CGImageDestinationSetProperties(destination, gifProps as CFDictionary)
        }

        public func append(_ image: CGImage) {
            CGImageDestinationAddImage(destination, image, frameProps)
            added += 1
        }

        public func finish() throws {
            guard added > 0 else {
                throw RenderError.writerFailed("GIF has no frames.")
            }
            // ImageIO requires the count declared at create time; if we added fewer
            // (cancel path shouldn't call finish), finalize may fail — handle cleanly.
            guard CGImageDestinationFinalize(destination) else {
                throw RenderError.writerFailed("Failed to finalize GIF.")
            }
        }

        public func cancel() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
