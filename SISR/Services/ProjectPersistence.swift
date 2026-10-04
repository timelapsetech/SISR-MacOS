import Foundation
import SISRKit

enum ProjectPersistence {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("SISR/Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(forSourcePath path: String) -> URL {
        let digest = path.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(64)
        return root.appendingPathComponent("\(digest).json")
    }

    static func save(_ state: SequenceProjectState) {
        guard let path = state.sourcePath else { return }
        let url = fileURL(forSourcePath: path)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(forSourcePath path: String) -> SequenceProjectState? {
        let url = fileURL(forSourcePath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SequenceProjectState.self, from: data)
    }
}
