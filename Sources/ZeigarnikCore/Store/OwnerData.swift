import Foundation
import GRDB

public struct Note: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let projectId: String
    public let day: String
    public let text: String
    public let createdAt: Date
}

public enum CalendarSyncState: String, Sendable, Codable {
    case pending, synced, notInCalendar, removedFromCalendar, unresolved
}

public struct ScheduledItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var projectId: String
    public var title: String
    public var start: Date
    public var duration: TimeInterval
    public var wantsCalendar: Bool
    public var eventIdentifier: String?
    public var syncState: CalendarSyncState
    public var syncDetail: String?
    public var deletedAt: Date?

    public init(id: UUID, projectId: String, title: String, start: Date, duration: TimeInterval, wantsCalendar: Bool,
                eventIdentifier: String?, syncState: CalendarSyncState, syncDetail: String?, deletedAt: Date?) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.start = start
        self.duration = duration
        self.wantsCalendar = wantsCalendar
        self.eventIdentifier = eventIdentifier
        self.syncState = syncState
        self.syncDetail = syncDetail
        self.deletedAt = deletedAt
    }
}

public enum CalendarOpKind: String, Sendable {
    case create, update, delete
}

public struct CalendarOp: Sendable, Equatable {
    public let seq: Int64
    public let itemId: UUID
    public let kind: CalendarOpKind
}

public enum OwnerDataError: Error, Equatable {
    case emptyText, unknownProject, unknownNote
}

extension Store {
    // MARK: Notes

    public func addNote(projectId: String, day: String, text: String, now: Date) throws -> Note {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OwnerDataError.emptyText }
        let note = Note(id: UUID(), projectId: projectId, day: day, text: trimmed, createdAt: now)
        try dbQueue.write { db in
            try Self.requireProject(db, projectId)
            try db.execute(sql: "INSERT INTO note (id, projectId, day, text, createdAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [note.id.uuidString, projectId, day, trimmed, now.timeIntervalSince1970])
        }
        return note
    }

    /// Changes only the text; the note keeps its day, project and creation time.
    public func updateNote(id: UUID, text: String) throws -> Note {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OwnerDataError.emptyText }
        return try dbQueue.write { db in
            try db.execute(sql: "UPDATE note SET text = ? WHERE id = ?", arguments: [trimmed, id.uuidString])
            guard db.changesCount > 0,
                  let note = try Row.fetchOne(db, sql: "SELECT * FROM note WHERE id = ?", arguments: [id.uuidString]).flatMap(Self.note)
            else { throw OwnerDataError.unknownNote }
            return note
        }
    }

    public func deleteNote(id: UUID) throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [id.uuidString]) }
    }

    public func notes(projectId: String) throws -> [Note] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM note WHERE projectId = ? ORDER BY createdAt DESC", arguments: [projectId]).compactMap(Self.note)
        }
    }

    public func notes(fromDay: String, toDay: String) throws -> [Note] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM note WHERE day >= ? AND day <= ? ORDER BY day, createdAt",
                             arguments: [fromDay, toDay]).compactMap(Self.note)
        }
    }

    // MARK: Pins and spec overrides

    public func setPinned(projectId: String, _ pinned: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE project SET pinned = ? WHERE id = ?", arguments: [pinned, projectId])
        }
    }

    public func setSpecOverride(projectId: String, specPath: String, _ state: OwnerSpecOverride?, note: String?) throws {
        try dbQueue.write { db in
            if let state {
                try db.execute(sql: """
                    INSERT INTO specOverride (projectId, specPath, state, note) VALUES (?, ?, ?, ?)
                    ON CONFLICT(projectId, specPath) DO UPDATE SET state = excluded.state, note = excluded.note
                    """, arguments: [projectId, specPath, state.rawValue, note])
            } else {
                try db.execute(sql: "DELETE FROM specOverride WHERE projectId = ? AND specPath = ?", arguments: [projectId, specPath])
            }
        }
    }

    // MARK: Scheduled items

    /// Saves the item and queues the calendar operation it implies in the same transaction.
    public func saveScheduledItem(_ item: ScheduledItem) throws {
        try dbQueue.write { db in
            try Self.requireProject(db, item.projectId)
            let existing = try Row.fetchOne(db, sql: "SELECT * FROM scheduledItem WHERE id = ?", arguments: [item.id.uuidString]).flatMap(Self.item)
            let hasPendingOp = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM calendarOp WHERE itemId = ?)",
                                                 arguments: [item.id.uuidString]) ?? false
            var stored = item
            stored.eventIdentifier = existing?.eventIdentifier ?? item.eventIdentifier
            let op: CalendarOpKind?
            if item.wantsCalendar {
                op = existing == nil ? .create : .update
                stored.syncState = .pending
                stored.syncDetail = nil
            } else if stored.eventIdentifier != nil || hasPendingOp {
                op = .delete
                stored.syncState = .pending
                stored.syncDetail = nil
            } else {
                op = nil
                stored.syncState = .notInCalendar
            }
            try Self.upsert(db, stored, createdAt: existing == nil)
            if let op { try Self.enqueue(db, item.id, op) }
        }
    }

    /// Keeps a tombstone (owner data is never pruned) and queues removal of the event.
    public func deleteScheduledItem(id: UUID, now: Date) throws {
        try dbQueue.write { db in
            guard var item = try Row.fetchOne(db, sql: "SELECT * FROM scheduledItem WHERE id = ?", arguments: [id.uuidString]).flatMap(Self.item) else { return }
            let hasPendingOp = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM calendarOp WHERE itemId = ?)", arguments: [id.uuidString]) ?? false
            item.deletedAt = now
            let needsDelete = item.wantsCalendar || item.eventIdentifier != nil || hasPendingOp
            if needsDelete { item.syncState = .pending }
            try Self.upsert(db, item, createdAt: false)
            if needsDelete { try Self.enqueue(db, id, .delete) }
        }
    }

    public func scheduledItem(id: UUID) throws -> ScheduledItem? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM scheduledItem WHERE id = ?", arguments: [id.uuidString]).flatMap(Self.item)
        }
    }

    public func scheduledItems(from: Date, to: Date) throws -> [ScheduledItem] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scheduledItem WHERE deletedAt IS NULL AND start >= ? AND start < ? ORDER BY start",
                             arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]).compactMap(Self.item)
        }
    }

    public func scheduledItems(projectId: String) throws -> [ScheduledItem] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scheduledItem WHERE deletedAt IS NULL AND projectId = ? ORDER BY start",
                             arguments: [projectId]).compactMap(Self.item)
        }
    }

    // MARK: Calendar operations

    public func pendingCalendarOps() throws -> [CalendarOp] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM calendarOp ORDER BY seq").compactMap { row in
                guard let id = UUID(uuidString: row["itemId"]), let kind = CalendarOpKind(rawValue: row["kind"]) else { return nil }
                return CalendarOp(seq: row["seq"], itemId: id, kind: kind)
            }
        }
    }

    public func finishCalendarOp(seq: Int64, item: ScheduledItem) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM calendarOp WHERE seq = ?", arguments: [seq])
            try Self.writeSync(db, item, after: seq, includeTime: false)
        }
    }

    /// `after`: the operation this result belongs to, or nil for a refresh pass. `includeTime` carries a move made in Calendar.
    public func writeSyncResult(_ item: ScheduledItem, after seq: Int64?, includeTime: Bool) throws {
        try dbQueue.write { db in try Self.writeSync(db, item, after: seq, includeTime: includeTime) }
    }

    /// Sync writes touch only sync columns, read before the calendar call. The owner may have saved or deleted the item
    /// meanwhile, which queues a newer operation; then only the event identifier is kept and the newer operation decides the rest.
    private static func writeSync(_ db: Database, _ item: ScheduledItem, after seq: Int64?, includeTime: Bool) throws {
        try db.execute(sql: "UPDATE scheduledItem SET eventIdentifier = ? WHERE id = ?", arguments: [item.eventIdentifier, item.id.uuidString])
        let superseded = try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM calendarOp WHERE itemId = ? AND seq > ?)",
                                           arguments: [item.id.uuidString, seq ?? -1]) ?? false
        guard !superseded else { return }
        let now = Date().timeIntervalSince1970
        if includeTime {
            try db.execute(sql: "UPDATE scheduledItem SET syncState = ?, syncDetail = ?, start = ?, duration = ?, updatedAt = ? WHERE id = ?",
                           arguments: [item.syncState.rawValue, item.syncDetail, item.start.timeIntervalSince1970, item.duration, now, item.id.uuidString])
        } else {
            try db.execute(sql: "UPDATE scheduledItem SET syncState = ?, syncDetail = ?, updatedAt = ? WHERE id = ?",
                           arguments: [item.syncState.rawValue, item.syncDetail, now, item.id.uuidString])
        }
    }

    /// Items whose event should be checked against the calendar: wanted in the calendar, not deleted, no pending operation.
    /// Items the owner wanted in the calendar while access was denied: queued for creation once access is granted.
    /// One transaction, touching only sync columns, so an edit made at the same moment is not overwritten.
    @discardableResult
    public func requeueItemsAwaitingCalendarAccess() throws -> Int {
        try dbQueue.write { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT id FROM scheduledItem s
                WHERE deletedAt IS NULL AND wantsCalendar = 1 AND syncState = 'notInCalendar'
                  AND NOT EXISTS (SELECT 1 FROM calendarOp o WHERE o.itemId = s.id)
                """).compactMap(UUID.init(uuidString:))
            for id in ids {
                try db.execute(sql: "UPDATE scheduledItem SET syncState = 'pending', syncDetail = NULL WHERE id = ?", arguments: [id.uuidString])
                try Self.enqueue(db, id, .create)
            }
            return ids.count
        }
    }

    public func calendarItemsToRefresh() throws -> [ScheduledItem] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM scheduledItem s
                WHERE deletedAt IS NULL AND wantsCalendar = 1 AND syncState IN ('synced', 'unresolved')
                  AND NOT EXISTS (SELECT 1 FROM calendarOp o WHERE o.itemId = s.id)
                ORDER BY start
                """).compactMap(Self.item)
        }
    }

    // MARK: Helpers

    func holdWriteLock(for seconds: TimeInterval, onLocked: () -> Void) throws {
        try dbQueue.write { _ in
            onLocked()
            Thread.sleep(forTimeInterval: seconds)
        }
    }

    private static func requireProject(_ db: Database, _ id: String) throws {
        guard try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM project WHERE id = ?)", arguments: [id]) == true else {
            throw OwnerDataError.unknownProject
        }
    }

    private static func enqueue(_ db: Database, _ id: UUID, _ kind: CalendarOpKind) throws {
        try db.execute(sql: "INSERT INTO calendarOp (itemId, kind, createdAt) VALUES (?, ?, ?)",
                       arguments: [id.uuidString, kind.rawValue, Date().timeIntervalSince1970])
    }

    private static func upsert(_ db: Database, _ item: ScheduledItem, createdAt isNew: Bool) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(sql: """
            INSERT INTO scheduledItem (id, projectId, title, start, duration, wantsCalendar, eventIdentifier, syncState, syncDetail, deletedAt, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET projectId = excluded.projectId, title = excluded.title, start = excluded.start,
              duration = excluded.duration, wantsCalendar = excluded.wantsCalendar, eventIdentifier = excluded.eventIdentifier,
              syncState = excluded.syncState, syncDetail = excluded.syncDetail, deletedAt = excluded.deletedAt, updatedAt = excluded.updatedAt
            """, arguments: [item.id.uuidString, item.projectId, item.title, item.start.timeIntervalSince1970, item.duration,
                             item.wantsCalendar, item.eventIdentifier, item.syncState.rawValue, item.syncDetail,
                             item.deletedAt?.timeIntervalSince1970, now, now])
        _ = isNew
    }

    private static func note(_ row: Row) -> Note? {
        guard let id = UUID(uuidString: row["id"]) else { return nil }
        return Note(id: id, projectId: row["projectId"], day: row["day"], text: row["text"],
                    createdAt: Date(timeIntervalSince1970: row["createdAt"]))
    }

    private static func item(_ row: Row) -> ScheduledItem? {
        guard let id = UUID(uuidString: row["id"]), let state = CalendarSyncState(rawValue: row["syncState"]) else { return nil }
        return ScheduledItem(id: id, projectId: row["projectId"], title: row["title"], start: Date(timeIntervalSince1970: row["start"]),
                             duration: row["duration"], wantsCalendar: row["wantsCalendar"], eventIdentifier: row["eventIdentifier"],
                             syncState: state, syncDetail: row["syncDetail"],
                             deletedAt: (row["deletedAt"] as Double?).map { Date(timeIntervalSince1970: $0) })
    }
}
