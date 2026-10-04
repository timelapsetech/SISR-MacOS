import Foundation

public struct DateParts: Equatable, Codable, Sendable {
    public var day: Bool
    public var month: Bool
    public var date: Bool
    public var year: Bool
    public var time: Bool

    public static let allOn = DateParts(day: true, month: true, date: true, year: true, time: true)

    public init(
        day: Bool = true,
        month: Bool = true,
        date: Bool = true,
        year: Bool = true,
        time: Bool = true
    ) {
        self.day = day
        self.month = month
        self.date = date
        self.year = year
        self.time = time
    }

    public var anyEnabled: Bool {
        day || month || date || year || time
    }

    public var allEnabled: Bool {
        day && month && date && year && time
    }
}

public enum DateOverlayFormatter {
    private static let rawFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    private static let rawDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM dd, yyyy hh:mma"
        return f
    }()

    private static let fullNoTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMMM dd, yyyy"
        return f
    }()

    public static func normalize(_ parts: DateParts?) -> DateParts {
        parts ?? .allOn
    }

    public static func parse(_ datetimeStr: String) -> Date? {
        guard !datetimeStr.isEmpty else { return nil }
        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy:MM:dd",
            "EEEE, MMMM dd, yyyy hh:mma",
            "EEEE, MMMM dd, yyyy",
            "MMMM dd, yyyy hh:mma",
            "MMMM dd, yyyy",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: datetimeStr) {
                return date
            }
        }
        return nil
    }

    public static func validate(_ dateStr: String) -> Bool {
        parse(dateStr) != nil
    }

    public static func format(_ datetimeStr: String, parts: DateParts? = nil) -> String {
        guard let dt = parse(datetimeStr) else { return datetimeStr }
        return format(date: dt, parts: parts)
    }

    public static func format(date dt: Date, parts: DateParts? = nil) -> String {
        let flags = normalize(parts)
        let showDay = flags.day
        let showMonth = flags.month
        let showDate = flags.date
        let showYear = flags.year
        let showTime = flags.time

        if !flags.anyEnabled { return "" }

        if flags.allEnabled {
            return fullFormatter.string(from: dt)
        }
        if showDay && showMonth && showDate && showYear && !showTime {
            return fullNoTime.string(from: dt)
        }

        let weekdayF = DateFormatter()
        weekdayF.locale = Locale(identifier: "en_US_POSIX")
        weekdayF.dateFormat = "EEEE"

        let monthF = DateFormatter()
        monthF.locale = Locale(identifier: "en_US_POSIX")
        monthF.dateFormat = "MMMM"

        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: "en_US_POSIX")
        dayF.dateFormat = "dd"

        let yearF = DateFormatter()
        yearF.locale = Locale(identifier: "en_US_POSIX")
        yearF.dateFormat = "yyyy"

        let timeF = DateFormatter()
        timeF.locale = Locale(identifier: "en_US_POSIX")
        timeF.dateFormat = "hh:mma"

        var monthDate: String?
        if showMonth && showDate {
            monthDate = "\(monthF.string(from: dt)) \(dayF.string(from: dt))"
        } else if showMonth {
            monthDate = monthF.string(from: dt)
        } else if showDate {
            monthDate = dayF.string(from: dt)
        }

        let calendar: String
        if let monthDate, showYear {
            if showMonth && !showDate {
                calendar = "\(monthDate) \(yearF.string(from: dt))"
            } else {
                calendar = "\(monthDate), \(yearF.string(from: dt))"
            }
        } else if let monthDate {
            calendar = monthDate
        } else if showYear {
            calendar = yearF.string(from: dt)
        } else {
            calendar = ""
        }

        var result: String
        if showDay && !calendar.isEmpty {
            result = "\(weekdayF.string(from: dt)), \(calendar)"
        } else if showDay {
            result = weekdayF.string(from: dt)
        } else {
            result = calendar
        }

        if showTime {
            let timeStr = timeF.string(from: dt)
            result = result.isEmpty ? timeStr : "\(result) \(timeStr)"
        }
        return result
    }

    /// Pick a drawtext fontsize that fits `text` in the cropped frame.
    public static func overlayFontSize(for text: String, frameWidth: Int, frameHeight: Int) -> Int {
        let base = max(12, Int(Double(min(frameWidth, frameHeight)) * 0.05))
        guard !text.isEmpty else { return base }
        let maxTextWidth = max(1.0, Double(frameWidth) * 0.85)
        let charWidthFactor = 0.6
        let estimated = Double(base) * charWidthFactor * Double(text.count)
        if estimated <= maxTextWidth { return base }
        let scaled = Int(maxTextWidth / (charWidthFactor * Double(text.count)))
        return max(12, scaled)
    }
}
