import Foundation

public enum OverlayType: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case date
    case frame

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .date: return "Date"
        case .frame: return "Frame"
        }
    }
}

public enum FrameNumberMode: String, Codable, Sendable {
    /// 1-based absolute index from the start of the loaded sequence.
    case countFromStart
    /// Use the source filename frame number.
    case useSourceNumbers

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case Self.countFromStart.rawValue, "countFromInPoint":
            self = .countFromStart
        case Self.useSourceNumbers.rawValue:
            self = .useSourceNumbers
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown FrameNumberMode: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Output playback/render speed via source-frame sampling. Output FPS is unchanged;
/// higher speeds skip frames so the result is shorter (e.g. 2× keeps every other frame).
public enum RenderSpeed: Int, Codable, CaseIterable, Sendable, Identifiable {
    case x1 = 1
    case x2 = 2
    case x3 = 3
    case x4 = 4
    case x5 = 5
    case x10 = 10

    public var id: Int { rawValue }

    public var displayName: String { "\(rawValue)×" }

    /// Source-frame stride used when sampling the in/out range.
    public var stride: Int { max(1, rawValue) }
}

public enum OutputCodec: String, Codable, CaseIterable, Sendable, Identifiable {
    case h264
    case hevc
    case prores
    case proresHQ
    case gif

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: return "Default (H.264)"
        case .hevc: return "HEVC"
        case .prores: return "ProRes"
        case .proresHQ: return "ProRes HQ"
        case .gif: return "GIF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .h264, .hevc: return "mp4"
        case .prores, .proresHQ: return "mov"
        case .gif: return "gif"
        }
    }

    /// Suffix used in output naming (Python parity).
    public var namingSuffix: String? {
        switch self {
        case .h264: return nil
        case .hevc: return "hevc"
        case .prores: return "prores"
        case .proresHQ: return "proreshq"
        case .gif: return "gif"
        }
    }
}

public struct RenderSettings: Codable, Equatable, Sendable {
    public var preset: OutputPreset
    public var customSize: PixelSize
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var landscape: Bool
    public var codec: OutputCodec
    public var fps: Double
    /// Source-frame sampling multiplier for faster output at the same FPS.
    public var speed: RenderSpeed
    public var overlay: OverlayType
    public var dateParts: DateParts
    public var frameNumberMode: FrameNumberMode
    /// Burn-in badge background alpha (0…1). Default 50%.
    public var overlayBackgroundOpacity: Double
    public var outputDirectoryBookmark: Data?
    public var outputDirectoryPath: String?
    public var outputBaseName: String
    /// Advanced H.264 / HEVC bitrate & quality overrides (`nil` fields = auto defaults).
    public var videoEncode: VideoEncodeSettings

    public static let `default` = RenderSettings()

    public init(
        preset: OutputPreset = .p1080,
        customSize: PixelSize = PixelSize(width: 1920, height: 1080),
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        landscape: Bool = true,
        codec: OutputCodec = .h264,
        fps: Double = 30,
        speed: RenderSpeed = .x1,
        overlay: OverlayType = .none,
        dateParts: DateParts = .allOn,
        frameNumberMode: FrameNumberMode = .countFromStart,
        overlayBackgroundOpacity: Double = 0.5,
        outputDirectoryBookmark: Data? = nil,
        outputDirectoryPath: String? = nil,
        outputBaseName: String = "render",
        videoEncode: VideoEncodeSettings = .automatic
    ) {
        self.preset = preset
        self.customSize = customSize
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.landscape = landscape
        self.codec = codec
        self.fps = fps
        self.speed = speed
        self.overlay = overlay
        self.dateParts = dateParts
        self.frameNumberMode = frameNumberMode
        self.overlayBackgroundOpacity = Self.clampOpacity(overlayBackgroundOpacity)
        self.outputDirectoryBookmark = outputDirectoryBookmark
        self.outputDirectoryPath = outputDirectoryPath
        self.outputBaseName = outputBaseName
        self.videoEncode = videoEncode
    }

    private enum CodingKeys: String, CodingKey {
        case preset, customSize, maxWidth, maxHeight, landscape, codec, fps, speed
        case overlay, dateParts, frameNumberMode, overlayBackgroundOpacity
        case outputDirectoryBookmark, outputDirectoryPath, outputBaseName
        case videoEncode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decode(OutputPreset.self, forKey: .preset)
        customSize = try c.decode(PixelSize.self, forKey: .customSize)
        maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth)
        maxHeight = try c.decodeIfPresent(Int.self, forKey: .maxHeight)
        landscape = try c.decodeIfPresent(Bool.self, forKey: .landscape) ?? true
        codec = try c.decode(OutputCodec.self, forKey: .codec)
        fps = try c.decode(Double.self, forKey: .fps)
        speed = try c.decodeIfPresent(RenderSpeed.self, forKey: .speed) ?? .x1
        overlay = try c.decode(OverlayType.self, forKey: .overlay)
        dateParts = try c.decodeIfPresent(DateParts.self, forKey: .dateParts) ?? .allOn
        frameNumberMode = try c.decodeIfPresent(FrameNumberMode.self, forKey: .frameNumberMode) ?? .countFromStart
        overlayBackgroundOpacity = Self.clampOpacity(
            try c.decodeIfPresent(Double.self, forKey: .overlayBackgroundOpacity) ?? 0.5
        )
        outputDirectoryBookmark = try c.decodeIfPresent(Data.self, forKey: .outputDirectoryBookmark)
        outputDirectoryPath = try c.decodeIfPresent(String.self, forKey: .outputDirectoryPath)
        outputBaseName = try c.decodeIfPresent(String.self, forKey: .outputBaseName) ?? "render"
        videoEncode = try c.decodeIfPresent(VideoEncodeSettings.self, forKey: .videoEncode) ?? .automatic
    }

    public static func clampOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }

    public var suggestedFPS: Double {
        codec == .gif ? 4 : fps
    }

    /// Absolute source indices to encode from `range`, stepping by `speed`.
    public func sampledSourceIndices(in range: TimelineRange) -> [Int] {
        let step = speed.stride
        guard range.outIndex >= range.inIndex else { return [] }
        return Array(stride(from: range.inIndex, through: range.outIndex, by: step))
    }

    public func outputFrameCount(in range: TimelineRange) -> Int {
        sampledSourceIndices(in: range).count
    }

    public func outputPixelSize(cropSize: PixelSize) -> PixelSize {
        switch preset {
        case .original:
            return cropSize.even
        case .custom:
            return customSize.even
        case .fitWithin:
            // Scale the crop/frame down to fit within max bounds — never crop, never upscale.
            guard cropSize.width > 0, cropSize.height > 0 else {
                return PixelSize(width: 0, height: 0)
            }
            let maxW = maxWidth.map { CGFloat($0) }
            let maxH = maxHeight.map { CGFloat($0) }
            var w = CGFloat(cropSize.width)
            var h = CGFloat(cropSize.height)
            var scale: CGFloat = 1
            if let maxW, let maxH, maxW > 0, maxH > 0 {
                scale = min(maxW / w, maxH / h)
            } else if let maxW, maxW > 0 {
                scale = maxW / w
            } else if let maxH, maxH > 0 {
                scale = maxH / h
            }
            guard scale.isFinite else {
                return cropSize.even
            }
            scale = min(1, scale)
            w *= scale
            h *= scale
            return PixelSize(
                width: GeometryUtil.safeInt(w.rounded()),
                height: GeometryUtil.safeInt(h.rounded())
            ).even
        default:
            guard var size = preset.fixedPixelSize else { return cropSize.even }
            if !landscape, let swapped = swappedSize(size) {
                size = swapped
            }
            return size.even
        }
    }

    private func swappedSize(_ size: PixelSize) -> PixelSize? {
        PixelSize(width: size.height, height: size.width)
    }
}
