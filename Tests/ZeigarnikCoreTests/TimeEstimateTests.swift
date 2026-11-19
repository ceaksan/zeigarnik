import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("TimeEstimate")
struct TimeEstimateTests {
    private var start: Date { isoDate("2026-11-18T10:00:00Z") }

    private var plusThree: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Etc/GMT-3")!
        return calendar
    }

    @Test func gapRuleWithinSession() {
        let times = [0.0, 600, 2400, 3000].map { start.addingTimeInterval($0) }
        #expect(sessionIntervals(times) == [
            DateInterval(start: start, duration: 600),
            DateInterval(start: start.addingTimeInterval(2400), duration: 600),
        ])
    }

    @Test func gapBetweenSessionsIsNotCredited() {
        let messages = [
            message(session: "a", at: start),
            message(session: "b", at: start.addingTimeInterval(884)),
        ]
        #expect(ownerIntervals(messages).isEmpty)
        #expect(unionIntervals(ownerIntervals(messages)).reduce(0) { $0 + $1.duration } == 0)
    }

    @Test func parallelSessionsCountOnce() {
        let first = [0.0, 600, 1200, 1800].map { message(session: "a", at: start.addingTimeInterval($0)) }
        let second = [600.0, 1200, 1800, 2400].map { message(session: "b", at: start.addingTimeInterval($0)) }
        let intervals = ownerIntervals(first + second)
        #expect(intervals == [DateInterval(start: start, duration: 2400)])
        #expect(intervals.reduce(0) { $0 + $1.duration } == 2400)
    }

    @Test func intervalSplitsAtLocalMidnight() {
        let messages = [
            message(session: "night", at: isoDate("2026-11-18T23:51:00+03:00")),
            message(session: "night", at: isoDate("2026-11-19T00:05:00+03:00")),
        ]
        #expect(secondsByDay(ownerIntervals(messages), calendar: plusThree) == [
            "2026-11-18": 540,
            "2026-11-19": 300,
        ])
        let untilMidnight = DateInterval(
            start: isoDate("2026-11-18T23:45:00+03:00"),
            end: isoDate("2026-11-19T00:00:00+03:00")
        )
        #expect(secondsByDay([untilMidnight], calendar: plusThree) == ["2026-11-18": 900])
    }

    @Test func gapBoundaryIsStrict() {
        #expect(sessionIntervals([start, start.addingTimeInterval(900)]).isEmpty)
        #expect(sessionIntervals([start, start.addingTimeInterval(899)]) == [DateInterval(start: start, duration: 899)])
    }

    @Test func sortsTimestampsAndIgnoresDuplicates() {
        #expect(sessionIntervals([start.addingTimeInterval(600), start, start]) == [
            DateInterval(start: start, duration: 600),
        ])
        #expect(sessionIntervals([]).isEmpty)
        #expect(sessionIntervals([start]).isEmpty)
    }

    @Test func unionMergesOverlappingNestedAndTouchingIntervals() {
        let intervals = [
            DateInterval(start: start.addingTimeInterval(1200), duration: 600),
            DateInterval(start: start.addingTimeInterval(300), duration: 120),
            DateInterval(start: start, duration: 900),
            DateInterval(start: start.addingTimeInterval(600), duration: 600),
            DateInterval(start: start.addingTimeInterval(2400), duration: 600),
        ]
        #expect(unionIntervals(intervals) == [
            DateInterval(start: start, duration: 1800),
            DateInterval(start: start.addingTimeInterval(2400), duration: 600),
        ])
        #expect(unionIntervals([]).isEmpty)
    }

    @Test func agentIsPartOfSessionIdentity() {
        let messages = [
            message(session: "shared", at: start, agent: .claude),
            message(session: "shared", at: start.addingTimeInterval(600), agent: .codex),
        ]
        #expect(ownerIntervals(messages).isEmpty)
    }

    @Test func unknownCwdStillContributesTime() {
        let messages = [
            message(session: "unknown", at: start, cwd: nil),
            message(session: "unknown", at: start.addingTimeInterval(600), cwd: nil),
        ]
        #expect(ownerIntervals(messages) == [DateInterval(start: start, duration: 600)])
    }

    @Test func configurableGapReachesOwnerIntervals() {
        let messages = [
            message(session: "a", at: start),
            message(session: "a", at: start.addingTimeInterval(1000)),
        ]
        #expect(ownerIntervals(messages).isEmpty)
        #expect(ownerIntervals(messages, gap: 1200) == [DateInterval(start: start, duration: 1000)])
    }

    private func message(session: String, at timestamp: Date, agent: Agent = .claude, cwd: String? = "/r/a") -> OwnerMessage {
        OwnerMessage(agent: agent, sessionId: session, timestamp: timestamp, cwd: cwd, source: .history)
    }
}
