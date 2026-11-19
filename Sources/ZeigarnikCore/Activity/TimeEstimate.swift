import Foundation

public func sessionIntervals(_ timestamps: [Date], gap: TimeInterval = 900) -> [DateInterval] {
    guard gap > 0 else { return [] }
    let sorted = timestamps.filter { $0.timeIntervalSinceReferenceDate.isFinite }.sorted()
    let intervals = zip(sorted, sorted.dropFirst()).compactMap { start, end -> DateInterval? in
        let duration = end.timeIntervalSince(start)
        guard duration > 0, duration < gap else { return nil }
        return DateInterval(start: start, end: end)
    }
    return unionIntervals(intervals)
}

public func unionIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
    let sorted = intervals.filter {
        $0.duration > 0 && $0.start.timeIntervalSinceReferenceDate.isFinite
            && $0.end.timeIntervalSinceReferenceDate.isFinite
    }.sorted { $0.start < $1.start }
    guard var current = sorted.first else { return [] }
    var merged: [DateInterval] = []
    for interval in sorted.dropFirst() {
        if interval.start <= current.end {
            current = DateInterval(start: current.start, end: max(current.end, interval.end))
        } else {
            merged.append(current)
            current = interval
        }
    }
    merged.append(current)
    return merged
}

public func secondsByDay(_ intervals: [DateInterval], calendar: Calendar) -> [String: TimeInterval] {
    var seconds: [String: TimeInterval] = [:]
    for interval in unionIntervals(intervals) {
        var position = interval.start
        while position < interval.end {
            guard let day = calendar.dateInterval(of: .day, for: position), day.end > position else {
                break
            }
            let end = min(day.end, interval.end)
            seconds[dayKey(position, calendar: calendar), default: 0] += end.timeIntervalSince(position)
            position = end
        }
    }
    return seconds
}

public func ownerIntervals(_ messages: [OwnerMessage], gap: TimeInterval = 900) -> [DateInterval] {
    var sessions: [Agent: [String: [Date]]] = [:]
    for message in messages {
        sessions[message.agent, default: [:]][message.sessionId, default: []].append(message.timestamp)
    }
    var intervals: [DateInterval] = []
    for agentSessions in sessions.values {
        for timestamps in agentSessions.values {
            intervals.append(contentsOf: sessionIntervals(timestamps, gap: gap))
        }
    }
    return unionIntervals(intervals)
}
