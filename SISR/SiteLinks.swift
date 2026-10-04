import AppKit
import Foundation

/// Public documentation URLs used in Help / Settings (App Store support & privacy).
enum SiteLinks {
    static let home = URL(string: "https://timelapsetech.github.io/SISR-MacOS/")!
    static let macGuide = URL(string: "https://timelapsetech.github.io/SISR-MacOS/guide.html")!
    static let privacy = URL(string: "https://timelapsetech.github.io/SISR-MacOS/privacy.html")!
    static let support = URL(string: "https://timelapsetech.github.io/SISR-MacOS/support.html")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
