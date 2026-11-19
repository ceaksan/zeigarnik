import Foundation

public struct MenubarSummary: Sendable, Equatable {
    public let upcoming: [ScheduledItem]
    public let pinned: [ProjectRow]
    public let uncommittedCount: Int
    public let readmeDriftCount: Int
    public let todayCount: Int
    public let lastScanAt: Date?
}

/// Today and the next seven days (at most five items), pinned projects, attention counts over active projects.
public func menubarSummary(rows: [ProjectRow], items: [ScheduledItem], lastScanAt: Date?, now: Date, calendar: Calendar) -> MenubarSummary {
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
    let windowEnd = calendar.date(byAdding: .day, value: 8, to: today) ?? today
    let live = items.filter { $0.deletedAt == nil }.sorted { $0.start < $1.start }
    let context = FilterContext(now: now, openNow: nil, roots: [])
    return MenubarSummary(
        upcoming: Array(live.filter { $0.start >= today && $0.start < windowEnd }.prefix(5)),
        pinned: rows.filter(\.pinned).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
        uncommittedCount: rows.filter { matches($0, .uncommitted, context) }.count,
        readmeDriftCount: rows.filter { matches($0, .readmeDrift, context) }.count,
        todayCount: live.filter { $0.start >= today && $0.start < tomorrow }.count,
        lastScanAt: lastScanAt
    )
}
