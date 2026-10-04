import Foundation
import Testing
@testable import SISRKit

@Suite("DateOverlayFormatter")
struct DateOverlayFormatterTests {
    private let raw = "2024:01:05 13:30:00"

    @Test func formatFullMatchesLegacy() {
        #expect(DateOverlayFormatter.format(raw) == "Friday, January 05, 2024 01:30PM")
        #expect(
            DateOverlayFormatter.format(raw, parts: DateParts(time: false))
                == "Friday, January 05, 2024"
        )
    }

    @Test func individualParts() {
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: true, month: false, date: false, year: false, time: false
        )) == "Friday")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: true, date: false, year: false, time: false
        )) == "January")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: false, date: true, year: false, time: false
        )) == "05")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: false, date: false, year: true, time: false
        )) == "2024")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: false, date: false, year: false, time: true
        )) == "01:30PM")
    }

    @Test func combinations() {
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: true, date: true, year: true, time: false
        )) == "January 05, 2024")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: true, date: false, year: true, time: false
        )) == "January 2024")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: true, month: true, date: true, year: false, time: true
        )) == "Friday, January 05 01:30PM")
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: false, date: true, year: true, time: false
        )) == "05, 2024")
    }

    @Test func allDisabledEmpty() {
        #expect(DateOverlayFormatter.format(raw, parts: DateParts(
            day: false, month: false, date: false, year: false, time: false
        )) == "")
    }

    @Test func parseAndValidate() {
        #expect(DateOverlayFormatter.parse(raw) != nil)
        #expect(DateOverlayFormatter.validate("Friday, January 05, 2024 01:30PM"))
        #expect(DateOverlayFormatter.validate("2024:01:05"))
        #expect(!DateOverlayFormatter.validate("not a date"))
    }

    @Test func fontSizeShrinksForLongText() {
        let short = DateOverlayFormatter.overlayFontSize(for: "2024", frameWidth: 640, frameHeight: 360)
        let long = DateOverlayFormatter.overlayFontSize(
            for: "Wednesday, September 30, 2026 12:00PM",
            frameWidth: 640,
            frameHeight: 360
        )
        #expect(short >= long)
        #expect(long >= 12)
    }
}
