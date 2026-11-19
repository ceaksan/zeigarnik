import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct MonthGridTests {
    let calendar = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_GB"))

    @Test func november2026StartsOnOctober26() {
        let g = monthGrid(year: 2026, month: 11, today: "2026-11-19", calendar: calendar)
        #expect(g.count == 42)
        #expect(g.first?.day == "2026-10-26")
        #expect(g.last?.day == "2026-12-06")
        #expect(g.filter(\.isToday).map(\.day) == ["2026-11-19"])
        #expect(g.filter(\.inMonth).count == 30)
        #expect(g.first(where: { $0.day == "2026-11-01" })?.dayOfMonth == 1)
    }

    @Test func monthStartingOnMondayHasNoLeadingDays() {
        let g = monthGrid(year: 2026, month: 6, today: "2026-11-19", calendar: calendar)
        #expect(g.first?.day == "2026-06-01")
        #expect(g.first?.inMonth == true)
        #expect(g.filter(\.isToday).isEmpty)
    }

    @Test func decemberRollsIntoNextYear() {
        let g = monthGrid(year: 2026, month: 12, today: "2026-11-19", calendar: calendar)
        #expect(g.first?.day == "2026-11-30")
        #expect(g.last?.day == "2027-01-10")
    }

    @Test func weekStartFollowsLocale() {
        #expect(calendar.firstWeekday == 2)
        #expect(calendar.locale?.identifier == "en_GB")
        let us = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_US"))
        #expect(us.firstWeekday == 1)
        #expect(monthGrid(year: 2026, month: 11, today: "2026-11-19", calendar: us).first?.day == "2026-11-01")
    }
}
