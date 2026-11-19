import Foundation
import Testing
@testable import ZeigarnikCore
@testable import ZeigarnikKit

@MainActor @Suite struct NoteDraftKitTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_795_046_400)

    func model(_ store: Store, checkReadme: Bool = true) -> AppModel {
        var settings = AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)
        settings.checkReadme = checkReadme
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return AppModel(store: store, settings: settings, coordinator: nil, calendarSync: nil,
                        home: URL(fileURLWithPath: "/nonexistent-home"), now: { Self.now }, calendar: calendar)
    }

    func seeded(_ store: Store) throws -> String {
        let id = try store.upsertProject(resolution: .new, path: "/r/orbit", displayName: "orbit", identity: nil)
        try store.writeSnapshot(ProjectSnapshot(
            projectId: id, day: "2026-11-19", scannedAt: Self.now,
            status: GitStatus(branch: "main", upstream: "origin/main", ahead: 2, behind: 0, changed: 0, untracked: 0, stash: 0),
            fetch: nil, lastFetchAt: nil, lastCommitAt: nil, readme: .behind(commits: 4, codeFiles: 3, manifestChanged: false),
            spec: nil, activeTasksOpen: nil, error: nil))
        return id
    }

    @Test func acceptingADraftTurnsItIntoTodaysNote() async throws {
        let store = try Store.inMemory()
        let id = try seeded(store)
        let model = model(store)
        await model.reload()
        let drafts = await model.projectDetail(id).drafts
        #expect(drafts.map(\.kind) == [.readme, .push])

        try model.acceptDraft(drafts[1], text: "Push after the review")
        let detail = await model.projectDetail(id)
        #expect(detail.notes.map(\.text) == ["Push after the review"])
        #expect(detail.notes.map(\.day) == ["2026-11-19"])
        #expect(detail.drafts.map(\.kind) == [.readme])

        model.dismissDraft(drafts[0])
        #expect(await model.projectDetail(id).drafts.isEmpty)
    }

    @Test func aStateThatClearsWithoutOpeningTheProjectBringsItsDraftBackLater() async throws {
        let store = try Store.inMemory()
        let id = try seeded(store)
        let model = model(store)
        await model.reload()
        let push = try #require(await model.projectDetail(id).drafts.first { $0.kind == .push })
        model.dismissDraft(push)

        func snapshot(ahead: Int) throws {
            try store.writeSnapshot(ProjectSnapshot(
                projectId: id, day: "2026-11-19", scannedAt: Self.now,
                status: GitStatus(branch: "main", upstream: "origin/main", ahead: ahead, behind: 0, changed: 0, untracked: 0, stash: 0),
                fetch: nil, lastFetchAt: nil, lastCommitAt: nil, readme: .current, spec: nil, activeTasksOpen: nil, error: nil))
        }
        try snapshot(ahead: 0)
        await model.reload()
        try snapshot(ahead: 3)
        await model.reload()
        #expect(await model.projectDetail(id).drafts.map(\.kind) == [.push])
    }

    @Test func readmeDraftsFollowTheReadmeCheck() async throws {
        let store = try Store.inMemory()
        let id = try seeded(store)
        let model = model(store, checkReadme: false)
        await model.reload()
        #expect(await model.projectDetail(id).drafts.map(\.kind) == [.push])
    }

    @Test func aWriteFromAnotherConnectionIsNoticedAndOwnWritesAreNot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zeigarnik-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("z.sqlite").path
        let appStore = try Store(path: path)
        let agentStore = try Store(path: path)
        let id = try seeded(appStore)
        let model = model(appStore)

        #expect(await model.checkExternalChanges() == false)
        try model.addNote(text: "from the app", projectId: id, context: .projectDetail)
        #expect(await model.checkExternalChanges() == false)

        let before = model.revision
        _ = try agentStore.addNote(projectId: id, day: "2026-11-19", text: "from an agent", now: Self.now)
        #expect(await model.checkExternalChanges() == true)
        #expect(model.revision > before)
        #expect(await model.projectDetail(id).notes.map(\.text).contains("from an agent"))
    }
}
