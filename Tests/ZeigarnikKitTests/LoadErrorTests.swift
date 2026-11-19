import Foundation
import GRDB
import Testing
@testable import ZeigarnikCore
@testable import ZeigarnikKit

@MainActor @Suite struct LoadErrorTests {
    @Test func unreadableDatabaseIsReportedAndKeepsTheLastRows() async throws {
        let store = try Store.inMemory()
        _ = try store.upsertProject(resolution: .new, path: "/r/tool", displayName: "tool", identity: nil)
        let model = AppModel(store: store, settings: AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false),
                             coordinator: nil, calendarSync: nil, home: URL(fileURLWithPath: "/nonexistent-home"))
        await model.reload()
        #expect(model.rows.map(\.displayName) == ["tool"])
        #expect(model.loadError == nil)

        try await store.dbQueue.write { try $0.execute(sql: "ALTER TABLE repoVisibility RENAME TO repoVisibilityGone") }
        await model.reload()
        #expect(model.loadError?.hasPrefix("Could not read projects from the database") == true)
        #expect(model.rows.map(\.displayName) == ["tool"])

        try await store.dbQueue.write { try $0.execute(sql: "ALTER TABLE repoVisibilityGone RENAME TO repoVisibility") }
        await model.reload()
        #expect(model.loadError == nil)
    }

    @Test func ownerDataFailuresAreReportedNotShownAsEmpty() async throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/tool", displayName: "tool", identity: nil)
        let model = AppModel(store: store, settings: AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false),
                             coordinator: nil, calendarSync: nil, home: URL(fileURLWithPath: "/nonexistent-home"))
        try model.addNote(text: "keep me", projectId: id, context: .projectDetail)
        let note = try #require(try store.notes(projectId: id).first)
        #expect(await model.projectDetail(id).notes.count == 1)
        #expect(model.ownerDataError == nil)

        try await store.dbQueue.write { try $0.execute(sql: "ALTER TABLE note RENAME TO noteGone") }
        _ = await model.projectDetail(id)
        #expect(model.ownerDataError?.hasPrefix("Could not read notes and schedules") == true)
        model.deleteNote(id: note.id)
        #expect(model.ownerDataError?.hasPrefix("Could not delete the note") == true)

        try await store.dbQueue.write { try $0.execute(sql: "ALTER TABLE noteGone RENAME TO note") }
        model.deleteNote(id: note.id)
        #expect(model.ownerDataError == nil)
        #expect(try store.notes(projectId: id).isEmpty)
    }
}
