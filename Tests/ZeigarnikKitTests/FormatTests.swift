import Foundation
import Testing
@testable import ZeigarnikKit

/// en_GB stands for a day-first locale with Monday weeks; en_US checks that formats follow the locale.
@Suite struct FormatTests {
    let zone = TimeZone(identifier: "Etc/GMT-3")!
    let dayFirst = Locale(identifier: "en_GB")
    let us = Locale(identifier: "en_US")
    var calendar: Calendar { zeigarnikCalendar(timeZone: zone, locale: dayFirst) }
    var usCalendar: Calendar { zeigarnikCalendar(timeZone: zone, locale: us) }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func spec(_ stage: SpecStage, declared: String? = "Accepted") -> SpecSummary {
        SpecSummary(specPath: "docs/s.md", planPath: nil, date: nil, title: "S", declared: declared, stage: stage, evidence: nil)
    }

    @Test func durations() {
        #expect(Format.duration(0, locale: us) == "≈0 min")
        #expect(Format.duration(44 * 60, locale: us) == "≈45 min")
        #expect(Format.duration(60, locale: us) == "≈5 min")
        #expect(Format.duration(59 * 60, locale: us) == "≈1 h")
        #expect(Format.duration(3 * 3600, locale: us) == "≈3 h")
        #expect(Format.duration(3.5 * 3600, locale: us) == "≈3.5 h")
        #expect(Format.duration(3.5 * 3600, locale: Locale(identifier: "de_DE")) == "≈3,5 h")
        #expect(Format.duration(48 * 3600, locale: us) == "≈48 h")
    }

    @Test func scanErrorMessagesUseSeparateLines() {
        let fetch = "fetch: fatal: could not read Username for https://github.com: terminal prompts disabled"
        let status = "status: unavailable\nadditional detail;without a space"
        #expect(Format.scanError("\(fetch); \(status); history: unavailable") == "\(fetch)\n\(status)\nhistory: unavailable")
        #expect(Format.scanError(fetch) == fetch)
        #expect(Format.scanError("") == "")
    }

    @Test func pushTexts() {
        #expect(Format.push(nil) == "?")
        #expect(Format.push(status(upstream: nil, ahead: nil, behind: nil)) == "no upstream")
        #expect(Format.push(status(branch: nil, upstream: nil, ahead: nil, behind: nil)) == "detached")
        #expect(Format.push(status(ahead: 2, behind: 1)) == "↑2 ↓1")
        #expect(Format.push(status(ahead: 2)) == "↑2")
        #expect(Format.push(status()) == "0")
        #expect(Format.pushNeedsAttention(status(upstream: nil, ahead: nil, behind: nil)))
        #expect(!Format.pushNeedsAttention(status()))
    }

    @Test func readmeTexts() {
        #expect(Format.readme(nil) == "unknown")
        #expect(Format.readme(.noReadme) == "none")
        #expect(Format.readme(.current) == "up to date")
        #expect(Format.readme(.behind(commits: 14, codeFiles: 9, manifestChanged: true)) == "14 commits behind, manifest changed")
        #expect(Format.readme(.behind(commits: 1, codeFiles: 1, manifestChanged: false)) == "1 commit behind")
    }

    @Test func readmeShortTexts() {
        #expect(Format.readmeShort(.behind(commits: 319, codeFiles: 40, manifestChanged: true)) == "319 behind")
        #expect(Format.readmeShort(.current) == "up to date")
        #expect(Format.readmeShort(nil) == "?")
    }

    @Test func specTexts() {
        #expect(Format.specShort(SpecHeadline(current: spec(.inProgress(done: 10, total: 11, external: 1)), lastDone: nil)) == "10/11, 1 external")
        #expect(Format.specShort(SpecHeadline(current: spec(.inProgress(done: 3, total: 5, external: 0)), lastDone: nil)) == "3/5")
        #expect(Format.specShort(SpecHeadline(current: spec(.inProgress(done: 0, total: 0, external: 0)), lastDone: nil)) == "no evidence")
        #expect(Format.specShort(SpecHeadline(current: spec(.design), lastDone: nil)) == "Design")
        #expect(Format.specShort(SpecHeadline(current: spec(.declaredDone(done: 5, total: 7)), lastDone: nil)) == "declared done, evidence 5/7")
        #expect(Format.specShort(SpecHeadline(current: spec(.done), lastDone: nil)) == "Done")
        #expect(Format.specShort(SpecHeadline(current: nil, lastDone: spec(.done))) == "Last spec done")
        #expect(Format.specShort(nil) == "-")
        #expect(Format.specLine(spec(.inProgress(done: 10, total: 11, external: 1))) == "Spec: Accepted · Evidence: 10/11, 1 external")
        #expect(Format.specLine(spec(.design, declared: nil)) == "Spec: not declared · Evidence: Design")
    }

    @Test func relativeDaysFollowLocale() {
        let now = date(2026, 11, 19, 10)
        #expect(Format.relativeDay(date(2026, 11, 19, 1), now: now, calendar: calendar) == "today")
        #expect(Format.relativeDay(date(2026, 11, 18, 23), now: now, calendar: calendar) == "yesterday")
        #expect(Format.relativeDay(date(2026, 11, 8), now: now, calendar: calendar) == "08/11")
        #expect(Format.relativeDay(date(2025, 11, 18), now: now, calendar: calendar) == "18/11/2025")
        #expect(Format.relativeDay(date(2026, 11, 8), now: now, calendar: usCalendar) == "11/8")
        #expect(Format.relativeDay(date(2025, 11, 18), now: now, calendar: usCalendar) == "11/18/25")
        #expect(Format.relativeDay(nil, now: now, calendar: calendar) == "-")
    }

    @Test func dayMonthAndTimeFollowLocale() {
        let morning = date(2026, 11, 8, 9, 5)
        #expect(Format.dayMonth(morning, calendar: calendar) == "08/11")
        #expect(Format.dayMonth(day: "2026-11-08", calendar: calendar) == "08/11")
        #expect(Format.dayMonth(day: "2026-11-08", calendar: usCalendar) == "11/8")
        #expect(Format.dayMonth(day: "not-a-day", calendar: calendar) == "not-a-day")
        #expect(Format.time(morning, calendar: calendar) == "09:05")
        #expect(Format.time(morning, calendar: usCalendar).replacingOccurrences(of: "\u{202F}", with: " ") == "9:05 AM")
        #expect(Format.dayMonthTime(morning, calendar: calendar) == "08/11 09:05")
    }

    @Test func titlesFollowLocale() {
        #expect(Format.dayTitle("2026-11-18", calendar: calendar) == "18 November 2026")
        #expect(Format.dayTitle("2026-11-18", calendar: usCalendar) == "November 18, 2026")
        #expect(Format.monthTitle(year: 2026, month: 2, calendar: calendar) == "February 2026")
        #expect(Format.dayTitle("bad", calendar: calendar) == "bad")
    }

    @Test func weekdayHeadersStartOnLocaleWeekStart() {
        #expect(weekdayHeaders(calendar: calendar) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(weekdayHeaders(calendar: usCalendar) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    @Test func architectureTexts() {
        let day = date(2026, 11, 12)
        #expect(Format.architecture(nil, calendar: calendar) == "unknown")
        #expect(Format.architecture(ArchitectureDoc.none, calendar: calendar) == "none")
        #expect(Format.architecture(.current(path: "architecture.md", updatedAt: day, commitsSince: 3), calendar: calendar) == "architecture.md · updated 12/11 · 3 commits since")
        #expect(Format.architecture(.current(path: "docs/architecture.md", updatedAt: nil, commitsSince: 0), calendar: calendar) == "docs/architecture.md · not committed yet")
        #expect(Format.architecture(.behind(path: "ARCHITECTURE.md", updatedAt: day, commitsSince: 14, newDirectories: ["Sources/Sync", "Tools"], newFiles: 7, manifestChanged: true), calendar: calendar)
                == "ARCHITECTURE.md · updated 12/11 · 14 commits since · 2 new folders, 7 new files, manifest changed")
        #expect(Format.architecture(.behind(path: "architecture.md", updatedAt: day, commitsSince: 1, newDirectories: ["src/x"], newFiles: 1, manifestChanged: false), calendar: calendar)
                == "architecture.md · updated 12/11 · 1 commit since · 1 new folder, 1 new file")
    }
}
