import Foundation
import ZeigarnikKit

enum UIFormat {
    static func dayMonthTime(_ date: Date, _ calendar: Calendar) -> String {
        Format.dayMonthTime(date, calendar: calendar)
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        Format.time(date, calendar: calendar)
    }

    static func dayMonth(_ day: String, _ calendar: Calendar) -> String {
        Format.dayMonth(day: day, calendar: calendar)
    }

    static func lastDays(_ count: Int, endingAt today: Date, _ calendar: Calendar) -> [String] {
        (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { dayKey($0, calendar: calendar) }
    }

    static func syncBadge(_ item: ScheduledItem) -> String {
        switch item.syncState {
        case .pending: "Pending"
        case .synced: "In Calendar"
        case .notInCalendar: "Not in Calendar"
        case .removedFromCalendar: "Removed from Calendar"
        case .unresolved: "Unresolved: \(item.syncDetail ?? "unknown")"
        }
    }

    static func agentName(_ agent: Agent?) -> String {
        switch agent {
        case .claude?: "claude"
        case .codex?: "codex"
        case nil: ""
        }
    }

    static func isOpen(_ id: String, _ state: OpenNowState?) -> Bool {
        guard case .known(let owners) = state else { return false }
        return owners.contains(.project(id))
    }
}
