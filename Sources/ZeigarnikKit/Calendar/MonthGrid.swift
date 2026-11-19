import Foundation

public struct GridDay: Sendable, Hashable {
    public let day: String
    public let dayOfMonth: Int
    public let inMonth: Bool
    public let isToday: Bool
}

public func zeigarnikCalendar(timeZone: TimeZone = .current, locale: Locale = .autoupdatingCurrent) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.locale = locale
    return calendar
}

/// 42 cells, six weeks, starting on the calendar's first weekday on or before the 1st of the month.
public func monthGrid(year: Int, month: Int, today: String, calendar: Calendar) -> [GridDay] {
    guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) else { return [] }
    let weekday = calendar.component(.weekday, from: first)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    return (0..<42).compactMap { offset in
        guard let date = calendar.date(byAdding: .day, value: offset - leading, to: first) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let key = dayKey(date, calendar: calendar)
        return GridDay(day: key, dayOfMonth: c.day ?? 0, inMonth: c.year == year && c.month == month, isToday: key == today)
    }
}
