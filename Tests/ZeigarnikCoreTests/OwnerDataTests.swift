import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct OwnerDataTests {
    let store: Store
    let project: String
    let now = Date(timeIntervalSince1970: 1_763_500_000)

    init() throws {
        store = try Store.inMemory()
        project = try store.upsertProject(resolution: .new, path: "/root/02_Products/orbit", displayName: "orbit", identity: nil)
    }

    func item(wantsCalendar: Bool = true, identifier: String? = nil, state: CalendarSyncState = .pending) -> ScheduledItem {
        ScheduledItem(id: UUID(), projectId: project, title: "orbit: Rust", start: now, duration: 3600,
                      wantsCalendar: wantsCalendar, eventIdentifier: identifier, syncState: state, syncDetail: nil, deletedAt: nil)
    }

    @Test func noteFromDayDetailKeepsClickedDay() throws {
        _ = try store.addNote(projectId: project, day: "2026-11-12", text: "  eski güne not  ", now: now)
        let notes = try store.notes(fromDay: "2026-11-12", toDay: "2026-11-12")
        #expect(notes.map(\.day) == ["2026-11-12"])
        #expect(notes.first?.text == "eski güne not")
        #expect(try store.notes(fromDay: "2026-11-13", toDay: "2026-11-30").isEmpty)
    }

    @Test func emptyNoteIsRejected() {
        #expect(throws: OwnerDataError.emptyText) { try store.addNote(projectId: project, day: "2026-11-12", text: "  \n", now: now) }
        #expect(throws: OwnerDataError.unknownProject) { try store.addNote(projectId: "nope", day: "2026-11-12", text: "x", now: now) }
    }

    @Test func notesAreNewestFirstAndDeletable() throws {
        let first = try store.addNote(projectId: project, day: "2026-11-12", text: "bir", now: now)
        _ = try store.addNote(projectId: project, day: "2026-11-13", text: "iki", now: now.addingTimeInterval(60))
        #expect(try store.notes(projectId: project).map(\.text) == ["iki", "bir"])
        try store.deleteNote(id: first.id)
        #expect(try store.notes(projectId: project).map(\.text) == ["iki"])
    }

    @Test func notesSurviveProjectGoingMissing() throws {
        _ = try store.addNote(projectId: project, day: "2026-11-12", text: "kalsın", now: now)
        try store.saveScheduledItem(item())
        try store.markMissing(exceptIds: [], underRoots: ["/root"], currentRoots: ["/root"])
        #expect(try store.notes(projectId: project).count == 1)
        #expect(try store.scheduledItems(projectId: project).count == 1)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first { $0.id == project }?.state == .missing)
    }

    @Test func pinRoundTrips() throws {
        try store.setPinned(projectId: project, true)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first { $0.id == project }?.pinned == true)
        try store.setPinned(projectId: project, false)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first { $0.id == project }?.pinned == false)
    }

    @Test func specOverrideFeedsScanOverrides() throws {
        try store.setSpecOverride(projectId: project, specPath: "docs/s.md", .done, note: "elle bitti")
        #expect(try store.specOverrides(projectId: project) == ["docs/s.md": .done])
        try store.setSpecOverride(projectId: project, specPath: "docs/s.md", nil, note: nil)
        #expect(try store.specOverrides(projectId: project).isEmpty)
    }

    @Test func savingNewItemQueuesCreate() throws {
        let new = item()
        try store.saveScheduledItem(new)
        #expect(try store.pendingCalendarOps().map(\.kind) == [.create])
        #expect(try store.scheduledItem(id: new.id)?.syncState == .pending)
    }

    @Test func editingItemQueuesUpdate() throws {
        var edited = item()
        try store.saveScheduledItem(edited)
        edited.title = "orbit: UI"
        try store.saveScheduledItem(edited)
        #expect(try store.pendingCalendarOps().map(\.kind) == [.create, .update])
        #expect(try store.scheduledItem(id: edited.id)?.title == "orbit: UI")
    }

    @Test func itemWithoutCalendarQueuesNothing() throws {
        let local = item(wantsCalendar: false)
        try store.saveScheduledItem(local)
        #expect(try store.pendingCalendarOps().isEmpty)
        #expect(try store.scheduledItem(id: local.id)?.syncState == .notInCalendar)
    }

    @Test func turningCalendarOffQueuesDelete() throws {
        var synced = item(identifier: "E1", state: .synced)
        try store.saveScheduledItem(synced)
        let ops = try store.pendingCalendarOps()
        for op in ops { try store.finishCalendarOp(seq: op.seq, item: synced) }
        synced.wantsCalendar = false
        try store.saveScheduledItem(synced)
        #expect(try store.pendingCalendarOps().map(\.kind) == [.delete])
    }

    @Test func deletingItemKeepsTombstoneAndQueuesDelete() throws {
        let doomed = item()
        try store.saveScheduledItem(doomed)
        try store.deleteScheduledItem(id: doomed.id, now: now)
        #expect(try store.scheduledItems(from: now.addingTimeInterval(-86400), to: now.addingTimeInterval(86400)).isEmpty)
        #expect(try store.scheduledItem(id: doomed.id)?.deletedAt != nil)
        #expect(try store.pendingCalendarOps().last?.kind == .delete)
    }

    @Test func finishingOpRemovesItAndWritesItem() throws {
        var new = item()
        try store.saveScheduledItem(new)
        let op = try #require(try store.pendingCalendarOps().first)
        new.eventIdentifier = "E1"
        new.syncState = .synced
        try store.finishCalendarOp(seq: op.seq, item: new)
        #expect(try store.pendingCalendarOps().isEmpty)
        #expect(try store.scheduledItem(id: new.id)?.eventIdentifier == "E1")
        #expect(try store.calendarItemsToRefresh().map(\.id) == [new.id])
    }

    @Test func secondWriterWaitsForBusyDatabase() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zg-busy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("z.sqlite").path
        let a = try Store(path: path)
        let b = try Store(path: path)
        let id = try a.upsertProject(resolution: .new, path: "/r/x", displayName: "x", identity: nil)
        let locked = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? a.holdWriteLock(for: 0.5) { locked.signal() }
            done.signal()
        }
        locked.wait()
        _ = try b.addNote(projectId: id, day: "2026-11-19", text: "bekledi", now: now)
        done.wait()
        #expect(try b.notes(projectId: id).count == 1)
    }
    @Test func readsReturnStoredRows() throws {
        try store.replaceCommitDays(projectId: project, ["2026-11-17": 3])
        #expect(try store.commitDays().map { "\($0.projectId == project) \($0.day) \($0.count)" } == ["true 2026-11-17 3"])
        let spec = SpecSummary(specPath: "docs/s.md", planPath: nil, date: nil, title: "S", declared: "Accepted", stage: .design, evidence: nil)
        try store.replaceSpecEvidence(projectId: project, [spec])
        #expect(try store.specSummaries(projectId: project) == [spec])
        let gone = try store.upsertProject(resolution: .new, path: "/root/old", displayName: "old", identity: nil)
        try store.recordPaths(projectId: project, ["/root/02_Products/orbit-old"])
        try store.markMissing(exceptIds: [project], underRoots: ["/root"], currentRoots: ["/root"])
        let current = try store.currentProjectPaths()
        #expect(current.map(\.path) == ["/root/02_Products/orbit"])
        #expect(!current.contains { $0.id == gone })
    }
}
