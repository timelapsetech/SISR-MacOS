import Foundation

/// Target average bitrates for delivery-friendly H.264 / HEVC encodes.
public enum VideoBitrate {
    /// Bits per second for H.264 by output pixel count.
    /// Rough ladder: 1080p ≈ 10 Mbps, 4K ≈ 15 Mbps, 8K ≈ 40 Mbps.
    public static func h264BitsPerSecond(width: Int, height: Int) -> Int {
        let pixels = max(1, width * height)
        switch pixels {
        case ..<(640 * 360):
            return 1_000_000
        case ..<(854 * 480):
            return 1_500_000
        case ..<(1280 * 720):
            return 2_500_000
        case ..<(1920 * 1080):
            return 5_000_000 // 720p-class
        case ..<(2560 * 1440):
            return 10_000_000 // 1080p (incl. 1080×1920 Instagram Story)
        case ..<(3840 * 2160):
            return 12_000_000 // 1440p
        case ..<(7680 * 4320):
            return 15_000_000 // 4K UHD
        default:
            return 40_000_000 // 8K-class
        }
    }

    /// HEVC roughly 65% of the H.264 ladder for similar perceived quality.
    public static func hevcBitsPerSecond(width: Int, height: Int) -> Int {
        Int(Double(h264BitsPerSecond(width: width, height: height)) * 0.65)
    }

    public static func defaultAverageMbps(codec: OutputCodec, width: Int, height: Int) -> Double {
        let bps: Int
        switch codec {
        case .h264:
            bps = h264BitsPerSecond(width: width, height: height)
        case .hevc:
            bps = hevcBitsPerSecond(width: width, height: height)
        case .prores, .proresHQ, .gif:
            return 0
        }
        return Double(bps) / 1_000_000
    }

    /// Peak rate ceiling used when max is left on Auto (~1.5× average).
    public static func defaultMaxMbps(averageMbps: Double) -> Double {
        max(averageMbps, (averageMbps * 1.5 * 10).rounded() / 10)
    }

    /// Default encoder quality hint (0…1) when the user leaves Quality on Auto.
    /// Not applied unless the user sets a quality override — bitrate remains the driver.
    public static let defaultQualityHint: Double = 0.75
}

/// Optional overrides for compressed video encodes (H.264 / HEVC).
/// `nil` fields mean “use the built-in defaults for this resolution/codec”.
public struct VideoEncodeSettings: Codable, Equatable, Sendable {
    /// Target average bitrate in megabits/sec.
    public var averageBitRateMbps: Double?
    /// Peak / max bitrate in megabits/sec.
    public var maxBitRateMbps: Double?
    /// Encoder quality hint 0…1 (`AVVideoQualityKey`). `nil` = omit (bitrate-driven).
    public var quality: Double?

    public static let automatic = VideoEncodeSettings()

    public init(
        averageBitRateMbps: Double? = nil,
        maxBitRateMbps: Double? = nil,
        quality: Double? = nil
    ) {
        self.averageBitRateMbps = averageBitRateMbps
        self.maxBitRateMbps = maxBitRateMbps
        self.quality = quality
    }

    public var usesAutomaticDefaults: Bool {
        averageBitRateMbps == nil && maxBitRateMbps == nil && quality == nil
    }

    public mutating func resetToDefaults() {
        averageBitRateMbps = nil
        maxBitRateMbps = nil
        quality = nil
    }

    public func resolvedAverageMbps(codec: OutputCodec, width: Int, height: Int) -> Double {
        if let averageBitRateMbps, averageBitRateMbps > 0 {
            return averageBitRateMbps
        }
        return VideoBitrate.defaultAverageMbps(codec: codec, width: width, height: height)
    }

    public func resolvedMaxMbps(codec: OutputCodec, width: Int, height: Int) -> Double {
        if let maxBitRateMbps, maxBitRateMbps > 0 {
            return maxBitRateMbps
        }
        let average = resolvedAverageMbps(codec: codec, width: width, height: height)
        return VideoBitrate.defaultMaxMbps(averageMbps: average)
    }

    public func resolvedAverageBitsPerSecond(codec: OutputCodec, width: Int, height: Int) -> Int {
        Int((resolvedAverageMbps(codec: codec, width: width, height: height) * 1_000_000).rounded())
    }

    public func resolvedMaxBitsPerSecond(codec: OutputCodec, width: Int, height: Int) -> Int {
        Int((resolvedMaxMbps(codec: codec, width: width, height: height) * 1_000_000).rounded())
    }

    /// Clamped 0…1 quality when overridden; `nil` means do not pass `AVVideoQualityKey`.
    public var resolvedQuality: Double? {
        guard let quality else { return nil }
        return min(1, max(0, quality))
    }
}
