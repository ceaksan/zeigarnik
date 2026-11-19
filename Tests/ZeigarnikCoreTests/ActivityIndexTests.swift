import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct ActivityIndexTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Etc/GMT-3")!
        return c
    }()

    func at(_ day: String, _ time: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "\(day) \(time)")!
    }

    func entries(_ owner: String?, other: String? = nil, agent: Agent = .claude, session: String, _ day: String, _ times: [String])
        -> [(message: OwnerMessage, projectId: String?, otherLabel: String?)] {
        times.map { (OwnerMessage(agent: agent, sessionId: session, timestamp: at(day, $0), cwd: nil, source: .history), owner, other) }
    }

    @Test func dayTotalIsUnionAcrossProjects() {
        let messages = entries("A", session: "s1", "2026-11-18", ["10:00", "10:10", "10:20", "10:30"])
            + entries("B", session: "s2", "2026-11-18", ["10:15", "10:25", "10:35", "10:45"])
        let index = buildActivityIndex(messages: messages, commitDays: [], calendar: calendar, gap: 900)
        #expect(index.slices(day: "2026-11-18").map(\.seconds) == [1800, 1800])
        #expect(index.dayTotal("2026-11-18") == 2700)
    }

    @Test func intervalCrossingMidnightCountsOnBothDays() {
        let messages = entries("A", session: "s1", "2026-11-18", ["23:51"]) + entries("A", session: "s1", "2026-11-19", ["00:05"])
        let index = buildActivityIndex(messages: messages, commitDays: [], calendar: calendar, gap: 900)
        #expect(index.slices(day: "2026-11-18").first?.seconds == 540)
        #expect(index.slices(day: "2026-11-19").first?.seconds == 300)
        #expect(index.dayTotal("2026-11-19") == 300)
    }

    @Test func otherBucketCountsTowardDayTotal() {
        let messages = entries(nil, other: "Desktop", session: "s1", "2026-11-18", ["09:00", "09:10"])
        let index = buildActivityIndex(messages: messages, commitDays: [], calendar: calendar, gap: 900)
        #expect(index.dayTotal("2026-11-18") == 600)
        #expect(index.slices(day: "2026-11-18").first?.owner == .other("Desktop"))
        #expect(index.otherTotals().first?.label == "Desktop")
        #expect(index.otherTotals().first?.seconds == 600)
    }

    @Test func sessionsCountedPerAgentPerDay() {
        let messages = entries("A", session: "c1", "2026-11-18", ["09:00"]) + entries("A", session: "c2", "2026-11-18", ["11:00"])
            + entries("A", agent: .codex, session: "x1", "2026-11-18", ["12:00"])
        let index = buildActivityIndex(messages: messages, commitDays: [("A", "2026-11-18", 2)], calendar: calendar, gap: 900)
        let slice = index.slices(day: "2026-11-18").first
        #expect(slice?.sessions == [.claude: 2, .codex: 1])
        #expect(slice?.commits == 2)
    }

    @Test func commitOnlyDayHasSliceWithZeroSeconds() {
        let index = buildActivityIndex(messages: [], commitDays: [("P", "2026-11-17", 3)], calendar: calendar, gap: 900)
        #expect(index.slices(day: "2026-11-17") == [DaySlice(owner: .project("P"), seconds: 0, sessions: [:], commits: 3)])
        #expect(index.dayTotal("2026-11-17") == 0)
    }

    @Test func projectSeriesIsZeroOnQuietDays() {
        let messages = entries("A", session: "s1", "2026-11-18", ["10:00", "10:10"])
        let index = buildActivityIndex(messages: messages, commitDays: [], calendar: calendar, gap: 900)
        #expect(index.projectSeries("A", days: ["2026-11-17", "2026-11-18", "2026-11-19"]) == [0, 600, 0])
        #expect(index.projectSeconds("A", fromDay: "2026-11-01", toDay: "2026-11-30") == 600)
        #expect(index.projectSeconds("A", fromDay: "2026-11-19", toDay: "2026-11-30") == 0)
    }
}
