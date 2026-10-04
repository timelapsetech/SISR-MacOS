import Foundation
import SISRKit

enum BookmarkStore {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) -> (url: URL, didStartAccessing: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        return (url, accessing)
    }

    /// Keeps security-scoped source + output folders alive for the duration of a render.
    @MainActor
    final class RenderAccess {
        private var urls: [URL] = []

        /// Returns a user-facing error if the output folder cannot be opened for writing.
        func begin(project: SequenceProject) -> String? {
            release()

            if let data = project.sourceBookmark, let resolved = resolve(data) {
                urls.append(resolved.url)
            } else if let path = project.sequence?.directory.path {
                let url = URL(fileURLWithPath: path)
                if url.startAccessingSecurityScopedResource() {
                    urls.append(url)
                }
            }

            let outputPath = project.render.outputDirectoryPath
            let sourcePath = project.sequence?.directory.path

            if let data = project.render.outputDirectoryBookmark, let resolved = resolve(data) {
                urls.append(resolved.url)
            } else if let outputPath, outputPath == sourcePath,
                      urls.contains(where: { $0.path == outputPath })
            {
                // User explicitly chose the sequence folder; source scope already covers it.
            } else if let outputPath {
                let url = URL(fileURLWithPath: outputPath)
                if url.startAccessingSecurityScopedResource() {
                    urls.append(url)
                } else {
                    return """
                    Can’t write to the output folder. Use Browse… under Destination to choose a folder \
                    so macOS can grant write access.
                    """
                }
            } else {
                return "No output folder is set. Choose one before rendering."
            }

            // Probe write permission before a long encode.
            if let outputPath {
                let probe = URL(fileURLWithPath: outputPath)
                    .appendingPathComponent(".sisr-write-probe-\(UUID().uuidString)")
                do {
                    try Data().write(to: probe, options: .withoutOverwriting)
                    try FileManager.default.removeItem(at: probe)
                } catch {
                    return """
                    Can’t write to “\(outputPath)”. Use Browse… to re-select the output folder \
                    so SISR can get permission, or pick a different folder.
                    """
                }
            }

            return nil
        }

        func release() {
            for url in urls {
                url.stopAccessingSecurityScopedResource()
            }
            urls.removeAll()
        }

        deinit {
            // stopAccessing is safe from any thread for balanced calls.
            for url in urls {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

@Observable
final class RecentDocumentsStore {
    private(set) var recent: [RecentItem] = []
    private let defaultsKey = "sisr.recentDocuments"
    private let limit = 12

    struct RecentItem: Codable, Identifiable, Equatable {
        var id: String { path }
        var path: String
        var bookmark: Data?
        var displayName: String
    }

    init() {
        load()
    }

    func add(url: URL, bookmark: Data?) {
        let item = RecentItem(
            path: url.path,
            bookmark: bookmark,
            displayName: url.lastPathComponent
        )
        recent.removeAll { $0.path == item.path }
        recent.insert(item, at: 0)
        if recent.count > limit {
            recent = Array(recent.prefix(limit))
        }
        save()
    }

    func clear() {
        recent = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data)
        else { return }
        recent = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
