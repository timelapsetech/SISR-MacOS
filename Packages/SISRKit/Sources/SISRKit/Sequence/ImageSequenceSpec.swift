import Foundation

public struct ImageSequenceFrame: Equatable, Sendable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let frameNumber: Int

    public init(url: URL, frameNumber: Int) {
        self.url = url
        self.frameNumber = frameNumber
    }
}

public struct ImageSequenceSpec: Equatable, Sendable {
    public let directory: URL
    public let prefix: String
    public let numberWidth: Int
    public let ext: String
    public let startNumber: Int
    public let frames: [ImageSequenceFrame]

    public var frameCount: Int { frames.count }

    public var pattern: String {
        "\(prefix)%0\(numberWidth)d\(ext)"
    }

    public var displayName: String {
        directory.lastPathComponent
    }

    public init(
        directory: URL,
        prefix: String,
        numberWidth: Int,
        ext: String,
        startNumber: Int,
        frames: [ImageSequenceFrame]
    ) {
        self.directory = directory
        self.prefix = prefix
        self.numberWidth = numberWidth
        self.ext = ext
        self.startNumber = startNumber
        self.frames = frames
    }
}

public struct UnprocessableImageSequenceError: Error, LocalizedError, Equatable {
    public let message: String
    public let directory: URL?

    public init(message: String, directory: URL? = nil) {
        self.message = message
        self.directory = directory
    }

    public var errorDescription: String? { message }
}
