import Foundation

public struct DaySlice: Sendable, Equatable {
    public let owner: ActivityOwner
    public let seconds: TimeInterval
    public let sessions: [Agent: Int]
    public let commits: Int

    public init(owner: ActivityOwner, seconds: TimeInterval, sessions: [Agent: Int], commits: Int) {
        self.owner = owner
        self.seconds = seconds
        self.sessions = sessions
        self.commits = commits
    }
}

/// Per-day activity built once per reload: seconds per owner and day, union totals per day, session and commit counts.
public struct ActivityIndex: Sendable {
    public static let empty = ActivityIndex(byDay: [:], totals: [:], ownerSeconds: [:])

    private let byDay: [String: [DaySlice]]
    private let totals: [String: TimeInterval]
    private let ownerSeconds: [ActivityOwner: [String: TimeInterval]]

    init(byDay: [String: [DaySlice]], totals: [String: TimeInterval], ownerSeconds: [ActivityOwner: [String: TimeInterval]]) {
        self.byDay = byDay
        self.totals = totals
        self.ownerSeconds = ownerSeconds
    }

    public func slices(day: String) -> [DaySlice] { byDay[day] ?? [] }

    public func dayTotal(_ day: String) -> TimeInterval { totals[day] ?? 0 }

    public func projectSeries(_ id: String, days: [String]) -> [TimeInterval] {
        let seconds = ownerSeconds[.project(id)] ?? [:]
        return days.map { seconds[$0] ?? 0 }
    }

    public func projectSeconds(_ id: String, fromDay: String, toDay: String) -> TimeInterval {
        (ownerSeconds[.project(id)] ?? [:]).filter { $0.key >= fromDay && $0.key <= toDay }.values.reduce(0, +)
    }

    public func otherTotals() -> [(label: String, seconds: TimeInterval)] {
        ownerSeconds.compactMap { owner, days -> (label: String, seconds: TimeInterval)? in
            guard case .other(let label) = owner else { return nil }
            return (label, days.values.reduce(0, +))
        }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.label < $1.label }
    }
}

public func buildActivityIndex(messages: [(message: OwnerMessage, projectId: String?, otherLabel: String?)],
                               commitDays: [(projectId: String, day: String, count: Int)],
                               calendar: Calendar, gap: TimeInterval) -> ActivityIndex {
    var byOwner: [ActivityOwner: [OwnerMessage]] = [:]
    var sessions: [ActivityOwner: [String: [Agent: Set<String>]]] = [:]
    for entry in messages {
        let owner: ActivityOwner = entry.projectId.map { .project($0) } ?? .other(entry.otherLabel ?? "?")
        byOwner[owner, default: []].append(entry.message)
        let day = dayKey(entry.message.timestamp, calendar: calendar)
        sessions[owner, default: [:]][day, default: [:]][entry.message.agent, default: []].insert(entry.message.sessionId)
    }

    var ownerSeconds: [ActivityOwner: [String: TimeInterval]] = [:]
    var allIntervals: [DateInterval] = []
    for (owner, ownerMessages) in byOwner {
        let intervals = ownerIntervals(ownerMessages, gap: gap)
        allIntervals.append(contentsOf: intervals)
        ownerSeconds[owner] = secondsByDay(intervals, calendar: calendar)
    }

    var commits: [ActivityOwner: [String: Int]] = [:]
    for entry in commitDays { commits[.project(entry.projectId), default: [:]][entry.day, default: 0] += entry.count }

    var byDay: [String: [DaySlice]] = [:]
    let owners = Set(byOwner.keys).union(commits.keys)
    for owner in owners {
        let days = Set((ownerSeconds[owner] ?? [:]).keys).union((sessions[owner] ?? [:]).keys).union((commits[owner] ?? [:]).keys)
        for day in days {
            let counts = (sessions[owner]?[day] ?? [:]).mapValues(\.count)
            byDay[day, default: []].append(DaySlice(owner: owner, seconds: ownerSeconds[owner]?[day] ?? 0,
                                                    sessions: counts, commits: commits[owner]?[day] ?? 0))
        }
    }
    for day in byDay.keys {
        byDay[day]?.sort { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : ownerName($0.owner) < ownerName($1.owner) }
    }
    return ActivityIndex(byDay: byDay, totals: secondsByDay(allIntervals, calendar: calendar), ownerSeconds: ownerSeconds)
}

private func ownerName(_ owner: ActivityOwner) -> String {
    switch owner {
    case .project(let id): id
    case .other(let label): "~" + label
    }
}
