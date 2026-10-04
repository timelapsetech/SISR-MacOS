import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else { return }
        NotificationCenter.default.post(name: .sisrOpenDirectoryURL, object: url)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Dev-only: `SISR.app --open /path` or a bare folder argument.
        // Release builds rely on Open panels / Finder / Dock (security-scoped access).
        if let path = Self.commandLineOpenPath() {
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .sisrOpenDirectoryURL, object: url)
            }
        }
        #endif
    }

    #if DEBUG
    /// `SISR.app --open /path/to/sequence`
    static func commandLineOpenPath() -> String? {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--open"), args.indices.contains(idx + 1) {
            return args[idx + 1]
        }
        if args.count >= 2 {
            let candidate = args[1]
            if candidate.hasPrefix("-") { return nil }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir),
               isDir.boolValue
            {
                return candidate
            }
        }
        return nil
    }
    #endif
}
