import Foundation
import Testing
@testable import ZeigarnikKit

final class FakeGateway: CalendarGateway, @unchecked Sendable {
    private let lock = NSLock()
    var accessState: CalendarAccess = .granted
    var events: [String: CalendarEvent] = [:]
    var throwOnLookup = false
    var creates = 0
    var removes = 0
    /// Runs once, outside the lock, in the middle of a reconcile: stands in for the owner editing at that moment.
    var duringLookup: (() -> Void)?
    var duringCreate: (() -> Void)?
    private var next = 0

    private func fire(_ hook: inout (() -> Void)?) {
        let run = lock.withLock { () -> (() -> Void)? in
            let h = hook
            hook = nil
            return h
        }
        run?()
    }

    struct Failure: Error {}

    func access() -> CalendarAccess { lock.withLock { accessState } }
    func requestAccess() async -> Bool { true }
    func calendars() -> [CalendarInfo] { [CalendarInfo(id: "cal", title: "Work", sourceTitle: "iCloud")] }

    func event(identifier: String) throws -> CalendarEvent? {
        fire(&duringLookup)
        return try lock.withLock {
            if throwOnLookup { throw Failure() }
            return events[identifier]
        }
    }

    func events(itemId: UUID, around: Date) throws -> [CalendarEvent] {
        try lock.withLock {
            if throwOnLookup { throw Failure() }
            return events.values.filter { $0.itemId == itemId && abs($0.start.timeIntervalSince(around)) <= 365 * 86_400 }
                .sorted { $0.identifier < $1.identifier }
        }
    }

    func create(_ draft: EventDraft, calendarId: String) throws -> String {
        fire(&duringCreate)
        return lock.withLock {
            creates += 1
            next += 1
            let id = "E\(next)"
            events[id] = CalendarEvent(identifier: id, calendarId: calendarId, title: draft.title, start: draft.start, end: draft.end, itemId: draft.itemId)
            return id
        }
    }

    func update(identifier: String, with draft: EventDraft) throws {
        try lock.withLock {
            guard let old = events[identifier] else { throw Failure() }
            events[identifier] = CalendarEvent(identifier: identifier, calendarId: old.calendarId, title: draft.title, start: draft.start, end: draft.end, itemId: draft.itemId)
        }
    }

    func remove(identifier: String) throws {
        lock.withLock {
            removes += 1
            events[identifier] = nil
        }
    }

    func put(_ id: String, itemId: UUID, start: Date, minutes: Double = 60) {
        lock.withLock { events[id] = CalendarEvent(identifier: id, calendarId: "cal", title: "x", start: start, end: start.addingTimeInterval(minutes * 60), itemId: itemId) }
    }
}

@Suite struct CalendarSyncTests {
    let store: Store
    let project: String
    let gateway = FakeGateway()
    let start = Date(timeIntervalSince1970: 1_763_632_800)

    init() throws {
        store = try Store.inMemory()
        project = try store.upsertProject(resolution: .new, path: "/r/orbit", displayName: "orbit", identity: nil)
    }

    func sync(target: String? = "cal") -> CalendarSync {
        CalendarSync(store: store, gateway: gateway, targetCalendarId: { target })
    }

    @discardableResult
    func save(_ id: UUID = UUID(), title: String = "orbit: Rust") throws -> ScheduledItem {
        let item = ScheduledItem(id: id, projectId: project, title: title, start: start, duration: 3600, wantsCalendar: true,
                                 eventIdentifier: nil, syncState: .pending, syncDetail: nil, deletedAt: nil)
        try store.saveScheduledItem(item)
        return item
    }

    func stored(_ id: UUID) throws -> ScheduledItem { try #require(try store.scheduledItem(id: id)) }

    @Test func createWritesEventWithItemId() async throws {
        let item = try save()
        _ = await sync().reconcile()
        #expect(gateway.events.count == 1)
        #expect(gateway.events.values.first?.itemId == item.id)
        #expect(gateway.events.values.first?.end == start.addingTimeInterval(3600))
        #expect(try stored(item.id).syncState == .synced)
        #expect(try stored(item.id).eventIdentifier == "E1")
        #expect(try store.pendingCalendarOps().isEmpty)
    }

    @Test func deleteDuringRefreshStaysDeletedAndRemovesTheEvent() async throws {
        let item = try save()
        _ = await sync().reconcile()
        #expect(try stored(item.id).syncState == .synced)
        let store = self.store
        gateway.duringLookup = { try? store.deleteScheduledItem(id: item.id, now: Date(timeIntervalSince1970: 1_763_640_000)) }
        _ = await sync().reconcile()
        #expect(try stored(item.id).deletedAt != nil)
        _ = await sync().reconcile()
        #expect(try stored(item.id).deletedAt != nil)
        #expect(gateway.events.isEmpty)
    }

    @Test func editDuringCreateKeepsTheNewTitleAndPushesIt() async throws {
        let item = try save(title: "old title")
        let store = self.store
        var edited = item
        edited.title = "new title"
        gateway.duringCreate = { try? store.saveScheduledItem(edited) }
        _ = await sync().reconcile()
        #expect(try stored(item.id).title == "new title")
        _ = await sync().reconcile()
        #expect(gateway.events.values.map(\.title) == ["new title"])
        #expect(try stored(item.id).syncState == .synced)
    }

    @Test func crashAfterWriteDoesNotDuplicate() async throws {
        let item = try save()
        gateway.put("X9", itemId: item.id, start: start)
        _ = await sync().reconcile()
        #expect(gateway.creates == 0)
        #expect(try stored(item.id).eventIdentifier == "X9")
        #expect(try stored(item.id).syncState == .synced)
    }

    @Test func deniedAccessSavesItemAsNotInCalendar() async throws {
        gateway.accessState = .denied
        let item = try save()
        _ = await sync().reconcile()
        #expect(try store.pendingCalendarOps().isEmpty)
        #expect(try stored(item.id).syncState == .notInCalendar)
        #expect(try stored(item.id).syncDetail?.contains("access") == true)
        #expect(gateway.creates == 0)
    }

    @Test func laterGrantDoesNotDuplicate() async throws {
        gateway.accessState = .denied
        var item = try save()
        _ = await sync().reconcile()
        gateway.accessState = .granted
        _ = await sync().reconcile()
        #expect(gateway.creates == 0)
        item.title = "orbit: UI"
        try store.saveScheduledItem(item)
        _ = await sync().reconcile()
        #expect(gateway.creates == 1)
        #expect(try stored(item.id).syncState == .synced)
    }

    @Test func eventMovedInCalendarUpdatesItemTime() async throws {
        let item = try save()
        _ = await sync().reconcile()
        let moved = start.addingTimeInterval(7200)
        gateway.put("E1", itemId: item.id, start: moved, minutes: 90)
        _ = await sync().reconcile()
        #expect(try stored(item.id).start == moved)
        #expect(try stored(item.id).duration == 5400)
        #expect(try stored(item.id).syncState == .synced)
    }

    @Test func changedIdentifierFoundByUUID() async throws {
        let item = try save()
        _ = await sync().reconcile()
        gateway.events["E1"] = nil
        gateway.put("E2", itemId: item.id, start: start)
        _ = await sync().reconcile()
        #expect(try stored(item.id).eventIdentifier == "E2")
        #expect(try stored(item.id).syncState == .synced)
    }

    @Test func goneEventMarksRemovedAndKeepsItem() async throws {
        let item = try save()
        _ = await sync().reconcile()
        gateway.events = [:]
        _ = await sync().reconcile()
        #expect(try stored(item.id).syncState == .removedFromCalendar)
        #expect(try store.scheduledItems(projectId: project).map(\.id) == [item.id])
        #expect(gateway.creates == 1)
    }

    @Test func storeErrorLeavesUnresolvedAndOpPending() async throws {
        gateway.throwOnLookup = true
        let item = try save()
        let summary = await sync().reconcile()
        #expect(try stored(item.id).syncState == .unresolved)
        #expect(try store.pendingCalendarOps().count == 1)
        #expect(gateway.creates == 0)
        #expect(summary.unresolved == 1)
    }

    @Test func twoEventsWithSameUUIDAreAmbiguous() async throws {
        let item = try save()
        gateway.put("A", itemId: item.id, start: start)
        gateway.put("B", itemId: item.id, start: start)
        _ = await sync().reconcile()
        #expect(try stored(item.id).syncState == .unresolved)
        #expect(gateway.creates == 0)
        #expect(gateway.removes == 0)
        #expect(gateway.events.count == 2)
    }

    @Test func deleteRemovesEventAndKeepsTombstone() async throws {
        let item = try save()
        _ = await sync().reconcile()
        try store.deleteScheduledItem(id: item.id, now: start)
        _ = await sync().reconcile()
        #expect(gateway.events.isEmpty)
        #expect(try store.pendingCalendarOps().isEmpty)
        #expect(try stored(item.id).deletedAt != nil)
    }

    @Test func editAfterEventDeletedRecreates() async throws {
        var item = try save()
        _ = await sync().reconcile()
        gateway.events = [:]
        item.title = "orbit: tekrar"
        try store.saveScheduledItem(item)
        _ = await sync().reconcile()
        #expect(gateway.creates == 2)
        #expect(try stored(item.id).syncState == .synced)
        #expect(gateway.events.values.first?.title == "orbit: tekrar")
    }

    @Test func noTargetCalendarIsUnresolvedNotDropped() async throws {
        let item = try save()
        _ = await sync(target: nil).reconcile()
        #expect(try stored(item.id).syncState == .unresolved)
        #expect(try store.pendingCalendarOps().count == 1)
        _ = await sync().reconcile()
        #expect(try stored(item.id).syncState == .synced)
    }
}
