import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct FormatterCacheTests {
    let plusThree = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_GB"))
    let newYork = zeigarnikCalendar(timeZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US"))

    @Test func sameCalendarAndPatternReuseOneFormatter() {
        #expect(Format.formatter("d.MM", plusThree) === Format.formatter("d.MM", plusThree))
        #expect(Format.formatter("d.MM", plusThree) !== Format.formatter("d.MM", newYork))
        #expect(Format.formatter("d.MM", plusThree) !== Format.formatter("d.MM.y", plusThree))
    }

    @Test func cachedFormattersKeepLocaleAndTimeZoneApart() {
        let date = Date(timeIntervalSince1970: 1_763_510_400) // 2025-11-19 00:00 UTC
        #expect(Format.dayMonth(date, calendar: plusThree) == "19/11")
        #expect(Format.dayMonth(date, calendar: newYork) == "11/18")
        #expect(Format.dayMonth(date, calendar: plusThree) == "19/11")
        let britishLocaleInNewYork = zeigarnikCalendar(timeZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_GB"))
        #expect(Format.dayMonth(date, calendar: britishLocaleInNewYork) == "18/11")
    }
}
