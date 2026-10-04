import Foundation

enum OutputFile {
    /// Ensure the destination path is clear for AVAssetWriter / ImageIO.
    /// Prefer delete; if that fails (sandbox / lock), fall back to a unique sibling name.
    static func prepareWritableURL(_ url: URL) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            return url
        }

        do {
            try fm.removeItem(at: url)
            return url
        } catch {
            // Existing file may be locked (Finder preview) or outside our scope.
            // Fall back to a non-colliding name in the same folder.
            let unique = uniqueSibling(of: url)
            if fm.fileExists(atPath: unique.path) {
                throw RenderError.writerFailed(
                    """
                    “\(url.lastPathComponent)” couldn’t be replaced \
                    (\(error.localizedDescription)). Close anything using that file, \
                    or use Browse… to pick an output folder SISR can write to.
                    """
                )
            }
            return unique
        }
    }

    private static func uniqueSibling(of url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let name = ext.isEmpty ? "\(base)_\(stamp)" : "\(base)_\(stamp).\(ext)"
        return dir.appendingPathComponent(name)
    }
}
