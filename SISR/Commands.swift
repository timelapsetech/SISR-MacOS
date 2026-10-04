import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Sequence…") {
                NotificationCenter.default.post(name: .sisrOpenSequence, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Close Sequence") {
                NotificationCenter.default.post(name: .sisrCloseSequence, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .sisrTogglePlay, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Play In to Out") {
                NotificationCenter.default.post(name: .sisrTogglePlayInOut, object: nil)
            }
            .keyboardShortcut(.space, modifiers: .shift)

            Button("Set In Point") {
                NotificationCenter.default.post(name: .sisrSetIn, object: nil)
            }
            .keyboardShortcut("i", modifiers: [])

            Button("Set Out Point") {
                NotificationCenter.default.post(name: .sisrSetOut, object: nil)
            }
            .keyboardShortcut("o", modifiers: [])

            Button("Clear In/Out") {
                NotificationCenter.default.post(name: .sisrClearInOut, object: nil)
            }
            .keyboardShortcut("x", modifiers: .option)

            Divider()

            Button("Go to Start") {
                NotificationCenter.default.post(name: .sisrGoToStart, object: nil)
            }
            .keyboardShortcut(.home, modifiers: [])

            Button("Go to In Point") {
                NotificationCenter.default.post(name: .sisrGoToIn, object: nil)
            }
            .keyboardShortcut("i", modifiers: .shift)

            Button("Go to Out Point") {
                NotificationCenter.default.post(name: .sisrGoToOut, object: nil)
            }
            .keyboardShortcut("o", modifiers: .shift)

            Button("Go to End") {
                NotificationCenter.default.post(name: .sisrGoToEnd, object: nil)
            }
            .keyboardShortcut(.end, modifiers: [])

            Divider()

            Button("Shuttle Reverse") {
                NotificationCenter.default.post(name: .sisrShuttleReverse, object: nil)
            }
            .keyboardShortcut("j", modifiers: [])

            Button("Stop") {
                NotificationCenter.default.post(name: .sisrShuttleStop, object: nil)
            }
            .keyboardShortcut("k", modifiers: [])

            Button("Shuttle Forward") {
                NotificationCenter.default.post(name: .sisrShuttleForward, object: nil)
            }
            .keyboardShortcut("l", modifiers: [])

            Divider()

            Button("Step Backward") {
                NotificationCenter.default.post(name: .sisrStepBack, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Step Forward") {
                NotificationCenter.default.post(name: .sisrStepForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }

        CommandMenu("Render") {
            Button("Render") {
                NotificationCenter.default.post(name: .sisrRender, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("SISR Mac Guide") {
                SiteLinks.open(SiteLinks.macGuide)
            }
            Button("Support") {
                SiteLinks.open(SiteLinks.support)
            }
            Button("Privacy Policy") {
                SiteLinks.open(SiteLinks.privacy)
            }
            Divider()
            Button("SISR Website") {
                SiteLinks.open(SiteLinks.home)
            }
        }
    }
}

extension Notification.Name {
    static let sisrOpenSequence = Notification.Name("sisr.openSequence")
    /// Posted with a `URL` object to load a sequence folder (CLI / Finder / dock).
    static let sisrOpenDirectoryURL = Notification.Name("sisr.openDirectoryURL")
    static let sisrCloseSequence = Notification.Name("sisr.closeSequence")
    static let sisrTogglePlay = Notification.Name("sisr.togglePlay")
    static let sisrTogglePlayInOut = Notification.Name("sisr.togglePlayInOut")
    static let sisrSetIn = Notification.Name("sisr.setIn")
    static let sisrSetOut = Notification.Name("sisr.setOut")
    static let sisrClearInOut = Notification.Name("sisr.clearInOut")
    static let sisrGoToStart = Notification.Name("sisr.goToStart")
    static let sisrGoToIn = Notification.Name("sisr.goToIn")
    static let sisrGoToOut = Notification.Name("sisr.goToOut")
    static let sisrGoToEnd = Notification.Name("sisr.goToEnd")
    static let sisrShuttleReverse = Notification.Name("sisr.shuttleReverse")
    static let sisrShuttleStop = Notification.Name("sisr.shuttleStop")
    static let sisrShuttleForward = Notification.Name("sisr.shuttleForward")
    static let sisrStepBack = Notification.Name("sisr.stepBack")
    static let sisrStepForward = Notification.Name("sisr.stepForward")
    static let sisrRender = Notification.Name("sisr.render")
    static let sisrToggleOriginal = Notification.Name("sisr.toggleOriginal")
}
