import Foundation

public struct ColorAdjustments: Codable, Equatable, Sendable {
    public var exposure: Double
    public var contrast: Double
    public var highlights: Double
    public var shadows: Double
    public var saturation: Double
    public var vibrance: Double
    public var temperature: Double
    public var tint: Double

    public static let identity = ColorAdjustments()

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        saturation: Double = 0,
        vibrance: Double = 0,
        temperature: Double = 0,
        tint: Double = 0
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.saturation = saturation
        self.vibrance = vibrance
        self.temperature = temperature
        self.tint = tint
    }

    public var isIdentity: Bool { self == .identity }
}

public struct DetailAdjustments: Codable, Equatable, Sendable {
    public var sharpen: Double
    public var noiseReduction: Double
    public var vignette: Double

    public static let identity = DetailAdjustments()

    public init(sharpen: Double = 0, noiseReduction: Double = 0, vignette: Double = 0) {
        self.sharpen = sharpen
        self.noiseReduction = noiseReduction
        self.vignette = vignette
    }

    public var isIdentity: Bool { self == .identity }
}

public struct DeflickerSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Rolling average window in frames (odd preferred).
    public var windowSize: Int
    /// Strength 0…1 of how much to pull toward the rolling average.
    public var strength: Double

    public static let off = DeflickerSettings(enabled: false, windowSize: 15, strength: 0.75)

    public init(enabled: Bool = false, windowSize: Int = 15, strength: Double = 0.75) {
        self.enabled = enabled
        self.windowSize = max(3, windowSize)
        self.strength = min(1, max(0, strength))
    }
}

public struct Adjustments: Codable, Equatable, Sendable {
    public var color: ColorAdjustments
    public var detail: DetailAdjustments
    public var deflicker: DeflickerSettings

    public static let identity = Adjustments()

    public init(
        color: ColorAdjustments = .identity,
        detail: DetailAdjustments = .identity,
        deflicker: DeflickerSettings = .off
    ) {
        self.color = color
        self.detail = detail
        self.deflicker = deflicker
    }
}
