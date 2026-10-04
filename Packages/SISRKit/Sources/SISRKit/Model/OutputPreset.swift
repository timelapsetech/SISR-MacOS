import CoreGraphics
import Foundation

public enum AspectRatioLock: String, Codable, CaseIterable, Sendable, Identifiable {
    case free
    case matchSource
    case ratio16x9
    case ratio4x3
    case ratio1x1
    case ratio9x16
    case ratio4x5
    case ratio239x1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .matchSource: return "Match source"
        case .ratio16x9: return "16:9"
        case .ratio4x3: return "4:3"
        case .ratio1x1: return "1:1"
        case .ratio9x16: return "9:16"
        case .ratio4x5: return "4:5"
        case .ratio239x1: return "2.39:1"
        }
    }

    /// Width / height. Nil for free / matchSource (resolved at use site).
    public var aspect: CGFloat? {
        switch self {
        case .free, .matchSource: return nil
        case .ratio16x9: return 16.0 / 9.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio1x1: return 1.0
        case .ratio9x16: return 9.0 / 16.0
        case .ratio4x5: return 4.0 / 5.0
        case .ratio239x1: return 2.39
        }
    }

    public func swapped() -> AspectRatioLock {
        switch self {
        case .ratio16x9: return .ratio9x16
        case .ratio9x16: return .ratio16x9
        case .ratio4x3: return .ratio4x5 // approximate portrait swap for UI
        case .ratio4x5: return .ratio4x3
        default: return self
        }
    }
}

public enum OutputSizeMode: String, Codable, Sendable, Equatable {
    case preset
    case original
    case custom
    case fitWithin
}

public struct PixelSize: Codable, Sendable, Equatable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    public var aspect: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    public var label: String { "\(width)×\(height)" }

    public var even: PixelSize {
        PixelSize(width: GeometryUtil.even(width), height: GeometryUtil.even(height))
    }
}

public enum OutputPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case uhd8k
    case dci4k
    case uhd4k
    case p1440
    case p1080
    case p720
    case p480
    case p360
    case ntsc
    case pal
    case instagramStory
    case square
    case portrait4x5
    case original
    case custom
    case fitWithin

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .uhd8k: return "8K UHD"
        case .dci4k: return "DCI 4K"
        case .uhd4k: return "4K UHD"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        case .ntsc: return "NTSC"
        case .pal: return "PAL"
        case .instagramStory: return "Instagram Story"
        case .square: return "Square"
        case .portrait4x5: return "Portrait 4:5"
        case .original: return "Native size"
        case .custom: return "Custom"
        case .fitWithin: return "Scale to fit"
        }
    }

    /// True when this mode keeps the full frame aspect (no forced crop preset).
    public var preservesSourceAspect: Bool {
        switch self {
        case .original, .fitWithin, .custom: return true
        default: return false
        }
    }

    public var fixedPixelSize: PixelSize? {
        switch self {
        case .uhd8k: return PixelSize(width: 7680, height: 4320)
        case .dci4k: return PixelSize(width: 4096, height: 2160)
        case .uhd4k: return PixelSize(width: 3840, height: 2160)
        case .p1440: return PixelSize(width: 2560, height: 1440)
        case .p1080: return PixelSize(width: 1920, height: 1080)
        case .p720: return PixelSize(width: 1280, height: 720)
        case .p480: return PixelSize(width: 854, height: 480)
        case .p360: return PixelSize(width: 640, height: 360)
        case .ntsc: return PixelSize(width: 720, height: 480)
        case .pal: return PixelSize(width: 720, height: 576)
        case .instagramStory: return PixelSize(width: 1080, height: 1920)
        case .square: return PixelSize(width: 1080, height: 1080)
        case .portrait4x5: return PixelSize(width: 1080, height: 1350)
        case .original, .custom, .fitWithin: return nil
        }
    }

    public var locksAspect: Bool {
        fixedPixelSize != nil
    }

    public var aspectLock: AspectRatioLock? {
        guard let size = fixedPixelSize else { return nil }
        let a = size.aspect
        if abs(a - 16.0 / 9.0) < 0.02 { return .ratio16x9 }
        if abs(a - 9.0 / 16.0) < 0.02 { return .ratio9x16 }
        if abs(a - 1.0) < 0.02 { return .ratio1x1 }
        if abs(a - 4.0 / 3.0) < 0.02 { return .ratio4x3 }
        if abs(a - 4.0 / 5.0) < 0.02 { return .ratio4x5 }
        if abs(a - 720.0 / 576.0) < 0.02 { return .ratio4x3 }
        return nil
    }

    /// Presets that share approximately the same aspect as `aspect`.
    public static func matchingAspect(_ aspect: CGFloat, tolerance: CGFloat = 0.03) -> [OutputPreset] {
        allCases.filter { preset in
            guard let size = preset.fixedPixelSize else { return false }
            return abs(size.aspect - aspect) < tolerance
                || abs(size.aspect - (1.0 / aspect)) < tolerance
        }
    }
}

public enum ResolutionFitness: String, Sendable, Equatable {
    case native
    case upscaled
    case tooSmall

    public var displayName: String {
        switch self {
        case .native: return "Native"
        case .upscaled: return "Upscaled"
        case .tooSmall: return "Heavy upscale"
        }
    }
}

public struct ResolutionCheck: Sendable, Equatable, Identifiable {
    public var id: String { preset.rawValue }
    public let preset: OutputPreset
    public let target: PixelSize
    public let crop: PixelSize
    public let fitness: ResolutionFitness
    /// Scale factor needed: target / crop ( >1 means upscaling).
    public let scaleFactor: CGFloat

    public var badgeLabel: String {
        switch fitness {
        case .native:
            return "Native"
        case .upscaled:
            let pct = Int((scaleFactor * 100).rounded())
            return "Upscaled \(pct)%"
        case .tooSmall:
            let pct = Int((scaleFactor * 100).rounded())
            return "Heavy upscale \(pct)%"
        }
    }

    /// True when the render will enlarge crop pixels to reach the target.
    public var willUpscale: Bool {
        scaleFactor > 1.001
    }

    public var warningSummary: String {
        guard willUpscale else {
            return "Crop \(crop.label) can deliver \(target.label) without upscaling."
        }
        let pct = Int((scaleFactor * 100).rounded())
        return "Render will upscale from crop \(crop.label) → \(target.label) (\(pct)%)."
    }

    public static func evaluate(crop: PixelSize, preset: OutputPreset) -> ResolutionCheck? {
        guard let target = preset.fixedPixelSize else { return nil }
        return evaluate(crop: crop, target: target, preset: preset)
    }

    public static func evaluate(crop: PixelSize, target: PixelSize, preset: OutputPreset = .custom) -> ResolutionCheck? {
        guard crop.width > 0, crop.height > 0, target.width > 0, target.height > 0 else { return nil }
        let scaleW = CGFloat(target.width) / CGFloat(crop.width)
        let scaleH = CGFloat(target.height) / CGFloat(crop.height)
        let scale = max(scaleW, scaleH)
        let fitness: ResolutionFitness
        if scale <= 1.0 {
            fitness = .native
        } else if scale <= 1.25 {
            fitness = .upscaled
        } else {
            // Warning only — rendering at this size is still allowed.
            fitness = .tooSmall
        }
        return ResolutionCheck(
            preset: preset,
            target: target,
            crop: crop,
            fitness: fitness,
            scaleFactor: scale
        )
    }
}
