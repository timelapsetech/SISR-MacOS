import Foundation

/// Finds a consecutive numbered image sequence FFmpeg/AVFoundation can render.
///
/// Port of `resolve_ffmpeg_image_sequence` from the Python core.
public enum SequenceScanner {
    public static let minSequenceFrames = 2

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "bmp", "heic", "heif",
    ]

    private static let namePattern = try! NSRegularExpression(
        pattern: #"^(?<prefix>.*?)(?<number>\d+)(?<ext>\.[^.]+)$"#
    )

    public static func scanDirectory(_ directory: URL) throws -> ImageSequenceSpec {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw UnprocessableImageSequenceError(
                message: "Could not read directory '\(directory.lastPathComponent)'.",
                directory: directory
            )
        }

        let imageURLs = contents.filter { url in
            imageExtensions.contains(url.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        let pairs = imageURLs.map { ($0, Optional<String>.none) }
        return try resolve(pairs, directory: directory)
    }

    /// Resolve from `(url, optionalDate)` pairs — mirrors the Python API.
    public static func resolve(
        _ imageDateFiles: [(URL, String?)],
        directory: URL? = nil
    ) throws -> ImageSequenceSpec {
        guard !imageDateFiles.isEmpty else {
            throw UnprocessableImageSequenceError(
                message: "No image files were found that can be rendered as a sequence."
            )
        }

        let directory = directory ?? imageDateFiles[0].0.deletingLastPathComponent()
        let dirName = directory.lastPathComponent.isEmpty
            ? directory.path
            : directory.lastPathComponent

        struct GroupKey: Hashable {
            let prefix: String
            let pad: Int
            let ext: String
        }

        var groups: [GroupKey: [(Int, URL)]] = [:]
        var unmatched: [String] = []

        for (url, _) in imageDateFiles {
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard let match = namePattern.firstMatch(in: name, range: range),
                  let prefixRange = Range(match.range(withName: "prefix"), in: name),
                  let numberRange = Range(match.range(withName: "number"), in: name),
                  let extRange = Range(match.range(withName: "ext"), in: name)
            else {
                unmatched.append(name)
                continue
            }
            let prefix = String(name[prefixRange])
            let numberStr = String(name[numberRange])
            let ext = String(name[extRange])
            guard let number = Int(numberStr) else {
                unmatched.append(name)
                continue
            }
            let key = GroupKey(prefix: prefix, pad: numberStr.count, ext: ext)
            groups[key, default: []].append((number, url))
        }

        var best: (GroupKey, [(Int, URL)])?
        var gappy: [String] = []
        var tooShort: [String] = []

        for (key, items) in groups {
            let sorted = items.sorted { $0.0 < $1.0 }
            let nums = sorted.map(\.0)
            if Set(nums).count != nums.count {
                gappy.append("\(key.prefix)\(String(repeating: "#", count: key.pad))\(key.ext) has duplicate frame numbers")
                continue
            }
            let expected = Array(nums[0]..<(nums[0] + nums.count))
            if nums != expected {
                let missing = expected.filter { !Set(nums).contains($0) }
                let sample = formatNameList(sorted.map { $0.1.lastPathComponent })
                let missingTxt = formatNameList(missing.map { String(format: "%0\(key.pad)d", $0) })
                gappy.append(
                    "\(key.prefix)\(String(repeating: "#", count: key.pad))\(key.ext) is not consecutive "
                        + "(missing \(missingTxt); found \(sample))"
                )
                continue
            }
            if sorted.count < minSequenceFrames {
                let sample = formatNameList(sorted.map { $0.1.lastPathComponent })
                tooShort.append(
                    "\(sorted.count) numbered file matching \(key.prefix)\(String(repeating: "#", count: key.pad))\(key.ext) (\(sample))"
                )
                continue
            }
            if best == nil || sorted.count > best!.1.count {
                best = (key, sorted)
            }
        }

        guard let best else {
            let found = formatNameList(imageDateFiles.map { $0.0.lastPathComponent })
            var reasons: [String] = []
            if !tooShort.isEmpty {
                reasons.append(
                    "A sequence needs at least 2 consecutive numbered frames; found "
                        + tooShort.joined(separator: "; ")
                )
            }
            if !gappy.isEmpty {
                reasons.append(gappy.joined(separator: "; "))
            }
            if reasons.isEmpty {
                reasons.append(
                    "Files need sequential numbers in the name (e.g. img_0001.jpg, img_0002.jpg, ...)"
                )
            }
            throw UnprocessableImageSequenceError(
                message: "Directory '\(dirName)' does not contain a processable image sequence. "
                    + "\(reasons.joined(separator: ". ")). Found: \(found).",
                directory: directory
            )
        }

        let (key, items) = best
        let frames = items.map { ImageSequenceFrame(url: $0.1, frameNumber: $0.0) }
        return ImageSequenceSpec(
            directory: directory,
            prefix: key.prefix,
            numberWidth: key.pad,
            ext: key.ext,
            startNumber: items[0].0,
            frames: frames
        )
    }

    private static func formatNameList(_ names: [String], limit: Int = 8) -> String {
        guard !names.isEmpty else { return "(none)" }
        let shown = names.prefix(limit)
        var text = shown.joined(separator: ", ")
        let extra = names.count - limit
        if extra > 0 {
            text += ", ... (\(extra) more)"
        }
        return text
    }
}
