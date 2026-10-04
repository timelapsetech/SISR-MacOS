import Foundation

public enum OutputNaming {
    /// Build `<base>_<options>.<ext>` matching Python `create_video_with_overlay`.
    public static func makeFilename(
        baseName: String,
        settings: RenderSettings,
        cropLabel: String?,
        outputSize: PixelSize?
    ) -> String {
        var options: [String] = []
        if let cropLabel, !cropLabel.isEmpty {
            options.append(cropLabel)
        } else if settings.preset != .original && settings.preset != .custom && settings.preset != .fitWithin {
            options.append(settings.preset.rawValue)
        }
        if settings.overlay != .none {
            options.append(settings.overlay.rawValue)
        }
        if let suffix = settings.codec.namingSuffix {
            options.append(suffix)
        }
        if settings.preset == .fitWithin, let outputSize {
            options.append("\(outputSize.width)x\(outputSize.height)")
        }

        let safeBase = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let ext = settings.codec.fileExtension
        if options.isEmpty {
            return "\(safeBase).\(ext)"
        }
        return "\(safeBase)_\(options.joined(separator: "_")).\(ext)"
    }

    public static func outputURL(settings: RenderSettings, cropLabel: String?, outputSize: PixelSize?) -> URL? {
        let name = makeFilename(
            baseName: settings.outputBaseName,
            settings: settings,
            cropLabel: cropLabel,
            outputSize: outputSize
        )
        guard let dir = settings.outputDirectoryPath else { return nil }
        return URL(fileURLWithPath: dir).appendingPathComponent(name)
    }
}
