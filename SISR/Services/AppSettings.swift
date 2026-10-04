import Foundation
import Observation
import SISRKit

@Observable
final class AppSettings {
    var appearance: AppAppearancePreference {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var defaultFPS: Double {
        didSet { UserDefaults.standard.set(defaultFPS, forKey: Keys.defaultFPS) }
    }

    var defaultCodec: OutputCodec {
        didSet { UserDefaults.standard.set(defaultCodec.rawValue, forKey: Keys.defaultCodec) }
    }

    var previewCacheLimit: Int {
        didSet { UserDefaults.standard.set(previewCacheLimit, forKey: Keys.previewCache) }
    }

    var defaultOutputPath: String? {
        didSet { UserDefaults.standard.set(defaultOutputPath, forKey: Keys.defaultOutput) }
    }

    /// When enabled, SISR may ask once for notification permission and alert on render complete.
    var notifyOnRenderComplete: Bool {
        didSet { UserDefaults.standard.set(notifyOnRenderComplete, forKey: Keys.notifyOnRenderComplete) }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = AppAppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        defaultFPS = defaults.object(forKey: Keys.defaultFPS) as? Double ?? 30
        if let raw = defaults.string(forKey: Keys.defaultCodec), let codec = OutputCodec(rawValue: raw) {
            defaultCodec = codec
        } else {
            defaultCodec = .h264
        }
        previewCacheLimit = defaults.object(forKey: Keys.previewCache) as? Int ?? 64
        defaultOutputPath = defaults.string(forKey: Keys.defaultOutput)
        if defaults.object(forKey: Keys.notifyOnRenderComplete) == nil {
            notifyOnRenderComplete = true
        } else {
            notifyOnRenderComplete = defaults.bool(forKey: Keys.notifyOnRenderComplete)
        }
    }

    private enum Keys {
        static let appearance = "sisr.appearance"
        static let defaultFPS = "sisr.defaultFPS"
        static let defaultCodec = "sisr.defaultCodec"
        static let previewCache = "sisr.previewCache"
        static let defaultOutput = "sisr.defaultOutput"
        static let notifyOnRenderComplete = "sisr.notifyOnRenderComplete"
    }
}
