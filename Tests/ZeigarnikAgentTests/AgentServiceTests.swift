import Foundation
import Testing
@testable import ZeigarnikAgent
@testable import ZeigarnikCore

@Suite struct AgentServiceTests {
    let store: Store
    let service: AgentService
    let orbit: String
    let lumen: String

    init() throws {
        store = try Store.inMemory()
        orbit = try store.upsertProject(resolution: .new, path: "/root/02_Products/orbit", displayName: "orbit", identity: nil)
        lumen = try store.upsertProject(resolution: .new, path: "/root/01_Core/lumen", displayName: "Lumen", identity: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        service = AgentService(store: store, now: { Date(timeIntervalSince1970: 1_795_046_400) }, calendar: calendar)
    }

    @Test func projectsAreNamedByIdNameOrPath() throws {
        #expect(try service.resolveProject(orbit) == orbit)
        #expect(try service.resolveProject("LUMEN") == lumen)
        #expect(try service.resolveProject("/root/01_Core/lumen/") == lumen)
        #expect(throws: AgentError.unknownProject("nova")) { try service.resolveProject("nova") }
    }

    @Test func twoProjectsWithOneNameAreAmbiguous() throws {
        _ = try store.upsertProject(resolution: .new, path: "/other/orbit", displayName: "orbit", identity: nil)
        #expect(throws: AgentError.ambiguousProject("orbit", ["/other/orbit", "/root/02_Products/orbit"])) { try service.resolveProject("orbit") }
    }

    @Test func addedNoteIsDatedTodayAndListedNewestFirst() throws {
        let first = try service.addNote(project: "orbit", text: "Rust port", day: "2026-11-10")
        let second = try service.addNote(project: "lumen", text: "  Release notes  ", day: nil)
        #expect(second.day == "2026-11-19")
        #expect(second.text == "Release notes")
        #expect(second.project == "Lumen")
        #expect(try service.notes(project: nil, since: nil, until: nil, limit: nil).map(\.id) == [second.id, first.id])
        #expect(try service.notes(project: "orbit", since: nil, until: nil, limit: nil).map(\.id) == [first.id])
        #expect(try service.notes(project: nil, since: "2026-11-15", until: nil, limit: nil).map(\.id) == [second.id])
        #expect(try service.notes(project: nil, since: nil, until: nil, limit: 1).map(\.id) == [second.id])
        #expect(throws: AgentError.invalidDay("19.11.2026")) { try service.addNote(project: "orbit", text: "x", day: "19.11.2026") }
    }

    @Test func notesAreFoundByAUniqueIdPrefix() throws {
        let note = try service.addNote(project: "orbit", text: "Rust port", day: nil)
        #expect(try service.note(String(note.id.prefix(8)).lowercased()).id == note.id)
        #expect(throws: AgentError.noteIdTooShort("ab")) { try service.note("ab") }
        #expect(throws: AgentError.unknownNote("ffffffff")) { try service.note("ffffffff") }
    }

    @Test func editingAndDeletingGoThroughTheStore() throws {
        let note = try service.addNote(project: "orbit", text: "Rust port", day: nil)
        #expect(try service.updateNote(note.id, text: "Rust port, phase 2").text == "Rust port, phase 2")
        #expect(throws: AgentError.emptyText) { try service.updateNote(note.id, text: " ") }
        _ = try service.deleteNote(note.id)
        #expect(try store.notes(projectId: orbit).isEmpty)
    }

    @Test func draftsComeFromTheLatestSnapshotAndRespectDismissals() throws {
        try store.writeSnapshot(ProjectSnapshot(
            projectId: orbit, day: "2026-11-19", scannedAt: Date(),
            status: GitStatus(branch: "main", upstream: "origin/main", ahead: 2, behind: 0, changed: 0, untracked: 0, stash: 0),
            fetch: nil, lastFetchAt: nil, lastCommitAt: nil, readme: .current, spec: nil, activeTasksOpen: nil, error: nil))
        let drafts = try service.drafts(project: nil)
        #expect(drafts.map(\.text) == ["Sync main: 2 commits to push."])
        #expect(drafts.map(\.project) == ["orbit"])
        try store.dismissNoteDraft(NoteDraft(projectId: orbit, kind: .push, text: "", fingerprint: "main:2:0"), now: Date())
        #expect(try service.drafts(project: "orbit").isEmpty)
    }
}
