import Foundation

/// How the per-frame brightness curve is smoothed into a target curve.
public enum DeflickerSmoothing: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Gaussian-weighted window: smooth, no ripple, keeps slow ramps.
    case gaussian
    /// Trimmed mean then light Gaussian: ignores outlier frames (a lone sun burst,
    /// headlights, a passing person) while still averaging sun / cloud alternation.
    case robust
    /// Plain rolling mean (the original SISR behavior).
    case average

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gaussian: return "Gaussian"
        case .robust: return "Robust (outlier-resistant)"
        case .average: return "Rolling average"
        }
    }
}

/// What each frame is balanced toward.
public enum DeflickerTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Smoothed version of the sequence itself — keeps sunsets and day-to-night ramps.
    case followScene
    /// One constant look for the whole range (median frame or a chosen reference frame).
    case locked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .followScene: return "Follow scene"
        case .locked: return "Lock look"
        }
    }
}

/// Which part of the output frame drives the brightness / color measurement.
public enum DeflickerMetering: String, Codable, CaseIterable, Sendable, Identifiable {
    case fullFrame
    /// Ignores the top third, where fast-moving clouds would otherwise read as flicker.
    case ignoreSky
    case center

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullFrame: return "Full frame"
        case .ignoreSky: return "Ignore sky (lower ⅔)"
        case .center: return "Center"
        }
    }
}

/// Spatially varying correction for partial cloud shadows and uneven light.
public enum DeflickerLocalGrid: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case coarse
    case fine

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .coarse: return "Coarse (4×3)"
        case .fine: return "Fine (8×6)"
        }
    }

    /// Grid dimensions in cells, or nil when off.
    public var dimensions: (columns: Int, rows: Int)? {
        switch self {
        case .off: return nil
        case .coarse: return (4, 3)
        case .fine: return (8, 6)
        }
    }
}

public struct DeflickerSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Temporal window in frames (odd).
    public var windowSize: Int
    /// 0…1 — how far each frame is pulled toward the target.
    public var strength: Double
    public var smoothing: DeflickerSmoothing
    public var target: DeflickerTarget
    /// Absolute sequence frame index used as the locked reference; nil = median of the range.
    public var referenceFrame: Int?
    public var metering: DeflickerMetering
    /// Match each frame's tonal distribution (hard sun vs. flat overcast contrast).
    public var matchContrast: Bool
    /// Smooth white-balance shifts (warm sun vs. blue shade, auto-WB jumps).
    public var balanceColor: Bool
    public var localGrid: DeflickerLocalGrid
    /// Remove camera exposure steps recorded in EXIF (manual-mode "Holy Grail" ramps).
    public var useCameraExposure: Bool
    /// Largest global exposure change applied to any frame, in stops.
    public var maxCorrectionEV: Double

    public static let off = DeflickerSettings(enabled: false)

    public init(
        enabled: Bool = false,
        windowSize: Int = 15,
        strength: Double = 0.75,
        smoothing: DeflickerSmoothing = .robust,
        target: DeflickerTarget = .followScene,
        referenceFrame: Int? = nil,
        metering: DeflickerMetering = .fullFrame,
        matchContrast: Bool = false,
        balanceColor: Bool = true,
        localGrid: DeflickerLocalGrid = .off,
        useCameraExposure: Bool = false,
        maxCorrectionEV: Double = 2
    ) {
        self.enabled = enabled
        self.windowSize = Self.normalizedWindow(windowSize)
        self.strength = min(1, max(0, strength))
        self.smoothing = smoothing
        self.target = target
        self.referenceFrame = referenceFrame
        self.metering = metering
        self.matchContrast = matchContrast
        self.balanceColor = balanceColor
        self.localGrid = localGrid
        self.useCameraExposure = useCameraExposure
        self.maxCorrectionEV = min(4, max(0.25, maxCorrectionEV))
    }

    public static func normalizedWindow(_ value: Int) -> Int {
        max(3, value | 1)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, windowSize, strength, smoothing, target, referenceFrame, metering
        case matchContrast, balanceColor, localGrid, useCameraExposure, maxCorrectionEV
    }

    /// Older autosaves only carry enabled / windowSize / strength.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DeflickerSettings()
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            windowSize: try c.decodeIfPresent(Int.self, forKey: .windowSize) ?? defaults.windowSize,
            strength: try c.decodeIfPresent(Double.self, forKey: .strength) ?? defaults.strength,
            smoothing: try c.decodeIfPresent(DeflickerSmoothing.self, forKey: .smoothing) ?? defaults.smoothing,
            target: try c.decodeIfPresent(DeflickerTarget.self, forKey: .target) ?? defaults.target,
            referenceFrame: try c.decodeIfPresent(Int.self, forKey: .referenceFrame),
            metering: try c.decodeIfPresent(DeflickerMetering.self, forKey: .metering) ?? defaults.metering,
            matchContrast: try c.decodeIfPresent(Bool.self, forKey: .matchContrast) ?? defaults.matchContrast,
            balanceColor: try c.decodeIfPresent(Bool.self, forKey: .balanceColor) ?? defaults.balanceColor,
            localGrid: try c.decodeIfPresent(DeflickerLocalGrid.self, forKey: .localGrid) ?? defaults.localGrid,
            useCameraExposure: try c.decodeIfPresent(Bool.self, forKey: .useCameraExposure)
                ?? defaults.useCameraExposure,
            maxCorrectionEV: try c.decodeIfPresent(Double.self, forKey: .maxCorrectionEV) ?? defaults.maxCorrectionEV
        )
    }
}

/// Starting points tuned for common time-lapse situations.
public enum DeflickerPreset: String, CaseIterable, Sendable, Identifiable {
    case standard
    case sunAndClouds
    case dayToNight
    case lockedLook
    case gentle
    case custom

    public var id: String { rawValue }

    public static let tuned: [DeflickerPreset] = [.standard, .sunAndClouds, .dayToNight, .lockedLook, .gentle]

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .sunAndClouds: return "Sun & clouds"
        case .dayToNight: return "Day-to-night (Holy Grail)"
        case .lockedLook: return "Locked look"
        case .gentle: return "Gentle"
        case .custom: return "Custom"
        }
    }

    public var summary: String {
        switch self {
        case .standard:
            return "Aperture / shutter flicker and auto-exposure jitter. Robust exposure and color smoothing."
        case .sunAndClouds:
            return "Full sun to full cloud frame to frame. Wide robust window plus contrast, color, and regional balance."
        case .dayToNight:
            return "Manual-mode exposure ramps. Undoes shutter / ISO / aperture steps from EXIF, then smooths."
        case .lockedLook:
            return "Every frame matched to one look — construction and long-term sequences across days and weather."
        case .gentle:
            return "Light touch for clean sequences; exposure only, keeps natural variation."
        case .custom:
            return "Hand-tuned settings."
        }
    }

    /// Settings for this preset, keeping `enabled` and the reference frame from `base`.
    public func settings(from base: DeflickerSettings) -> DeflickerSettings {
        var s: DeflickerSettings
        switch self {
        case .custom:
            return base
        case .standard:
            s = DeflickerSettings(
                windowSize: 15, strength: 1, smoothing: .robust, target: .followScene,
                metering: .fullFrame, matchContrast: false, balanceColor: true,
                localGrid: .off, useCameraExposure: false, maxCorrectionEV: 2
            )
        case .sunAndClouds:
            s = DeflickerSettings(
                windowSize: 31, strength: 1, smoothing: .robust, target: .followScene,
                metering: .fullFrame, matchContrast: true, balanceColor: true,
                localGrid: .coarse, useCameraExposure: false, maxCorrectionEV: 2.5
            )
        case .dayToNight:
            s = DeflickerSettings(
                windowSize: 25, strength: 1, smoothing: .gaussian, target: .followScene,
                metering: .fullFrame, matchContrast: false, balanceColor: true,
                localGrid: .off, useCameraExposure: true, maxCorrectionEV: 3
            )
        case .lockedLook:
            s = DeflickerSettings(
                windowSize: 15, strength: 1, smoothing: .robust, target: .locked,
                metering: .fullFrame, matchContrast: true, balanceColor: true,
                localGrid: .coarse, useCameraExposure: false, maxCorrectionEV: 3
            )
        case .gentle:
            s = DeflickerSettings(
                windowSize: 9, strength: 0.75, smoothing: .gaussian, target: .followScene,
                metering: .fullFrame, matchContrast: false, balanceColor: false,
                localGrid: .off, useCameraExposure: false, maxCorrectionEV: 1
            )
        }
        s.enabled = base.enabled
        s.referenceFrame = base.referenceFrame
        return s
    }

    /// The tuned preset whose parameters equal `settings`, else `.custom`.
    public static func matching(_ settings: DeflickerSettings) -> DeflickerPreset {
        tuned.first { $0.settings(from: settings) == settings } ?? .custom
    }
}
