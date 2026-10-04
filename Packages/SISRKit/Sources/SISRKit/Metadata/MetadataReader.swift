import CoreGraphics
import Foundation
import ImageIO

public enum MetadataReader {
    /// Extract date/time matching Python `extract_date_time` priority:
    /// Exif DateTimeOriginal → TIFF DateTime → file modification time.
    public static func extractDateTime(from url: URL) -> String {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        {
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               !original.isEmpty
            {
                return original
            }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let dateTime = tiff[kCGImagePropertyTIFFDateTime] as? String,
               !dateTime.isEmpty
            {
                return dateTime
            }
        }

        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let mod = values.contentModificationDate
        {
            return formatRaw(mod)
        }
        return formatRaw(Date())
    }

    public static func imagePixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat
        else {
            return nil
        }

        // Apply orientation if present (EXIF orientation 5–8 swap dimensions).
        if let orient = props[kCGImagePropertyOrientation] as? UInt32 {
            switch orient {
            case 5, 6, 7, 8:
                return CGSize(width: h, height: w)
            default:
                break
            }
        }
        return CGSize(width: w, height: h)
    }

    private static func formatRaw(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.string(from: date)
    }
}
