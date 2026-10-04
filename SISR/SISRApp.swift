import SwiftUI
import SISRKit

@main
struct SISRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    @State private var recent = RecentDocumentsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(recent)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
