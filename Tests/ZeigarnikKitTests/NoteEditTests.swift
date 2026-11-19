import Foundation
import Testing
@testable import ZeigarnikCore
@testable import ZeigarnikKit

@MainActor @Suite struct NoteEditTests {
    @Test func editedNoteShowsInTheProjectDetail() async throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/orbit", displayName: "orbit", identity: nil)
        let model = AppModel(store: store, settings: AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false),
                             coordinator: nil, calendarSync: nil, home: URL(fileURLWithPath: "/nonexistent-home"))
        try model.addNote(text: "first", projectId: id, context: .projectDetail)
        let note = try #require(await model.projectDetail(id).notes.first)
        let before = model.revision
        try model.updateNote(id: note.id, text: "second")
        #expect(await model.projectDetail(id).notes.map(\.text) == ["second"])
        #expect(model.revision > before)
        #expect(throws: ModelError.emptyText) { try model.updateNote(id: note.id, text: "  ") }
    }
}
