import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct MenubarSummaryTests {
    let calendar = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_GB"))
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))! }

    func item(_ dayOffset: Int, hour: Int = 12) -> ScheduledItem {
        let base = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: base)!
        return ScheduledItem(id: UUID(), projectId: "p", title: "t\(dayOffset)", start: start, duration: 3600, wantsCalendar: false,
                             eventIdentifier: nil, syncState: .notInCalendar, syncDetail: nil, deletedAt: nil)
    }

    @Test func upcomingIsTodayAndNextSevenDaysAtMostFive() {
        let items = [item(-1), item(0, hour: 1), item(3), item(8)] + (1...6).map { item($0) }
        let s = menubarSummary(rows: [], items: items, lastScanAt: nil, now: now, calendar: calendar)
        #expect(s.upcoming.count == 5)
        #expect(s.upcoming.first?.title == "t0")
        #expect(!s.upcoming.contains { $0.title == "t-1" || $0.title == "t8" })
        #expect(s.upcoming.map(\.start) == s.upcoming.map(\.start).sorted())
    }

    @Test func badgeCountsOnlyTodaysItems() {
        let s = menubarSummary(rows: [], items: [item(0, hour: 9), item(0, hour: 20), item(1)], lastScanAt: nil, now: now, calendar: calendar)
        #expect(s.todayCount == 2)
    }

    @Test func attentionCountsExcludeMissing() {
        let dirty = status(changed: 3)
        let rows = [row("a", status: dirty), row("b", state: .missing, status: dirty),
                    row("c", pinned: true, readme: .behind(commits: 2, codeFiles: 1, manifestChanged: false))]
        let s = menubarSummary(rows: rows, items: [], lastScanAt: nil, now: now, calendar: calendar)
        #expect(s.uncommittedCount == 1)
        #expect(s.readmeDriftCount == 1)
        #expect(s.pinned.map(\.id) == ["c"])
    }
}
