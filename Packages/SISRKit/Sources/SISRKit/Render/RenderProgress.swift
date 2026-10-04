import AppKit
import Foundation

public struct RenderProgress: Sendable {
    public var framesDone: Int
    public var framesTotal: Int
    public var framesPerSecond: Double
    public var elapsed: TimeInterval
    public var eta: TimeInterval?
    public var outputByteCount: Int64?
    public var latestThumbnail: NSImage?
    public var isFinished: Bool
    public var isCancelled: Bool
    public var errorMessage: String?
    public var outputURL: URL?
    /// Short phase label shown while framesDone is still 0 (e.g. deflicker).
    public var statusMessage: String?

    public var fraction: Double {
        guard framesTotal > 0 else { return 0 }
        return min(1, Double(framesDone) / Double(framesTotal))
    }

    public init(
        framesDone: Int = 0,
        framesTotal: Int = 0,
        framesPerSecond: Double = 0,
        elapsed: TimeInterval = 0,
        eta: TimeInterval? = nil,
        outputByteCount: Int64? = nil,
        latestThumbnail: NSImage? = nil,
        isFinished: Bool = false,
        isCancelled: Bool = false,
        errorMessage: String? = nil,
        outputURL: URL? = nil,
        statusMessage: String? = nil
    ) {
        self.framesDone = framesDone
        self.framesTotal = framesTotal
        self.framesPerSecond = framesPerSecond
        self.elapsed = elapsed
        self.eta = eta
        self.outputByteCount = outputByteCount
        self.latestThumbnail = latestThumbnail
        self.isFinished = isFinished
        self.isCancelled = isCancelled
        self.errorMessage = errorMessage
        self.outputURL = outputURL
        self.statusMessage = statusMessage
    }
}

public enum RenderError: Error, LocalizedError, Equatable {
    case noSequence
    case invalidOutput
    case writerFailed(String)
    case cancelled
    case frameFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .noSequence: return "No image sequence is loaded."
        case .invalidOutput: return "Output path is invalid. Choose an output folder with Browse…"
        case .writerFailed(let msg): return msg
        case .cancelled: return "Render was cancelled."
        case .frameFailed(let i): return "Failed to process frame \(i)."
        }
    }
}
