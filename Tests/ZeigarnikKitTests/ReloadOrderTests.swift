import Foundation
import Testing
@testable import ZeigarnikCore
@testable import ZeigarnikKit

@MainActor @Suite struct ReloadOrderTests {
    @Test func anOlderReloadFinishingLastDoesNotOverwriteANewerOne() throws {
        let store = try Store.inMemory()
        let model = AppModel(store: store, settings: AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false),
                             coordinator: nil, calendarSync: nil, home: URL(fileURLWithPath: "/nonexistent-home"))
        let empty = buildActivityIndex(messages: [], commitDays: [], calendar: model.calendar, gap: model.gap)
        let older = try store.projectRows(today: model.today, gap: model.gap)
        _ = try store.upsertProject(resolution: .new, path: "/r/tool", displayName: "tool", identity: nil)
        let newer = try store.projectRows(today: model.today, gap: model.gap)

        let first = model.beginReload()
        let second = model.beginReload()
        model.finishReload(second, data: .success((newer, empty)), problems: [])
        model.finishReload(first, data: .success((older, empty)), problems: [])

        #expect(model.rows.map(\.displayName) == ["tool"])
    }
}
