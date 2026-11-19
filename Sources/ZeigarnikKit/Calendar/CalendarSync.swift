import Foundation

public struct ReconcileSummary: Sendable, Equatable {
    public var processed: Int
    public var unresolved: Int
}

/// Zeigarnik is the source of truth. Pending operations are applied in order, then synced items are checked
/// against the calendar. Nothing is created or removed unless the lookup was conclusive.
/// `reconcile()` has no suspension point, so the actor runs reconciliations strictly one at a time.
public actor CalendarSync {
    private let store: Store
    private let gateway: any CalendarGateway
    private let targetCalendarId: @Sendable () -> String?

    private enum Located {
        case found(CalendarEvent), gone, ambiguous, inconclusive(String)
    }

    public init(store: Store, gateway: any CalendarGateway, targetCalendarId: @escaping @Sendable () -> String?) {
        self.store = store
        self.gateway = gateway
        self.targetCalendarId = targetCalendarId
    }

    public func reconcile() -> ReconcileSummary {
        var summary = ReconcileSummary(processed: 0, unresolved: 0)
        var blocked: Set<UUID> = []
        for op in (try? store.pendingCalendarOps()) ?? [] {
            guard !blocked.contains(op.itemId), var item = try? store.scheduledItem(id: op.itemId) else { continue }
            if let pendingDetail = apply(op, to: &item) {
                item.syncState = .unresolved
                item.syncDetail = pendingDetail
                try? store.writeSyncResult(item, after: op.seq, includeTime: false)
                blocked.insert(op.itemId)
                summary.unresolved += 1
            } else {
                try? store.finishCalendarOp(seq: op.seq, item: item)
                summary.processed += 1
            }
        }
        for var item in (try? store.calendarItemsToRefresh()) ?? [] where !blocked.contains(item.id) {
            switch locate(item) {
            case .found(let event):
                item.eventIdentifier = event.identifier
                item.start = event.start
                item.duration = event.end.timeIntervalSince(event.start)
                item.syncState = .synced
                item.syncDetail = nil
            case .gone:
                item.eventIdentifier = nil
                item.syncState = .removedFromCalendar
                item.syncDetail = nil
            case .ambiguous:
                item.syncState = .unresolved
                item.syncDetail = Self.ambiguousText
                summary.unresolved += 1
            case .inconclusive:
                continue
            }
            try? store.writeSyncResult(item, after: nil, includeTime: true)
            summary.processed += 1
        }
        return summary
    }

    /// Applies one operation to the item. Returns nil when the operation is finished, or the reason it stays pending.
    private func apply(_ op: CalendarOp, to item: inout ScheduledItem) -> String? {
        let access = gateway.access()
        if op.kind == .delete {
            if access != .granted, item.eventIdentifier == nil {
                item.syncState = .notInCalendar
                item.syncDetail = nil
                return nil
            }
            switch locate(item) {
            case .found(let event):
                do { try gateway.remove(identifier: event.identifier) } catch { return "Could not delete the event: \(error)" }
                fallthrough
            case .gone:
                item.eventIdentifier = nil
                item.syncState = .notInCalendar
                item.syncDetail = nil
                return nil
            case .ambiguous: return Self.ambiguousText
            case .inconclusive(let reason): return reason
            }
        }
        switch access {
        case .denied:
            item.syncState = .notInCalendar
            item.syncDetail = "No calendar access"
            return nil
        case .notDetermined:
            return "Calendar access not requested yet"
        case .granted:
            break
        }
        let draft = EventDraft(itemId: item.id, title: item.title, start: item.start, end: item.start.addingTimeInterval(item.duration))
        switch locate(item) {
        case .found(let event):
            do { try gateway.update(identifier: event.identifier, with: draft) } catch { return "Could not update the event: \(error)" }
            item.eventIdentifier = event.identifier
        case .gone:
            guard let calendarId = targetCalendarId() else { return "No target calendar selected" }
            do { item.eventIdentifier = try gateway.create(draft, calendarId: calendarId) } catch { return "Could not add the event: \(error)" }
        case .ambiguous:
            return Self.ambiguousText
        case .inconclusive(let reason):
            return reason
        }
        item.syncState = .synced
        item.syncDetail = nil
        return nil
    }

    /// Identifier first (it can change after a calendar move or sync), then the item's UUID within one year of its start.
    private func locate(_ item: ScheduledItem) -> Located {
        guard gateway.access() == .granted else { return .inconclusive("No calendar access") }
        if let identifier = item.eventIdentifier, let event = try? gateway.event(identifier: identifier),
           event.itemId == nil || event.itemId == item.id {
            return .found(event)
        }
        do {
            let matches = try gateway.events(itemId: item.id, around: item.start)
            switch matches.count {
            case 0: return .gone
            case 1: return .found(matches[0])
            default: return .ambiguous
            }
        } catch {
            return .inconclusive("Could not read the calendar: \(error)")
        }
    }

    private static let ambiguousText = "Several calendar events point to the same item"
}
