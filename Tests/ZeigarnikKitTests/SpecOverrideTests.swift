import Foundation
import Testing
@testable import ZeigarnikCore
@testable import ZeigarnikKit

@MainActor @Suite struct SpecOverrideTests {
    @Test func markDoneIsVisibleBeforeAnotherScan() async throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/sample", displayName: "sample", identity: nil)
        let path = "docs/specs/sample.md"
        let spec = SpecSummary(specPath: path, planPath: nil, date: nil, title: "Sample", declared: nil, stage: .design, evidence: nil)
        try store.replaceSpecEvidence(projectId: id, [spec])
        let model = AppModel(store: store, settings: .firstRun(home: URL(fileURLWithPath: "/nonexistent-home"), fileManager: .default),
                             coordinator: nil, calendarSync: nil)
        model.setSpecOverride(projectId: id, specPath: path, .done, note: nil)
        #expect(try store.specOverrides(projectId: id)[path] == .done)
        #expect(model.revision == 1)
        #expect(model.ownerDataError == nil)
        #expect(await model.projectDetail(id).specs.first?.stage == .done)
        #expect(await model.projectDetail(id).visibleSpecs().isEmpty)
        #expect(await model.projectDetail(id).visibleSpecs(showCompleted: true).map(\.specPath) == [path])
        let reopened = AppModel(store: store, settings: model.settings, coordinator: nil, calendarSync: nil)
        #expect(await reopened.projectDetail(id).visibleSpecs().isEmpty)
        model.setSpecOverride(projectId: id, specPath: path, .notDone, note: nil)
        #expect(await model.projectDetail(id).visibleSpecs().map(\.stage) == [.design])
        model.setSpecOverride(projectId: id, specPath: path, nil, note: nil)
        #expect(try store.specOverrides(projectId: id).isEmpty)
        #expect(await model.projectDetail(id).visibleSpecs().map(\.stage) == [.design])
    }

    @Test func naturallyDoneCanBeReopenedAndResetWithoutChangingOtherProjects() async throws {
        let store = try Store.inMemory()
        let first = try store.upsertProject(resolution: .new, path: "/r/first", displayName: "First", identity: nil)
        let second = try store.upsertProject(resolution: .new, path: "/r/second", displayName: "Second", identity: nil)
        let path = "docs/plans/sample.md"
        let evidence = PlanEvidence(tasks: [TaskEvidenceDetail(number: 1, title: "Sample", evidence: .done, resolvedPaths: ["src/sample.swift"], matchedCommits: [])])
        let spec = SpecSummary(specPath: path, planPath: path, date: nil, title: "Sample", declared: nil, stage: .done, evidence: evidence)
        for id in [first, second] { try store.replaceSpecEvidence(projectId: id, [spec]) }
        let model = AppModel(store: store, settings: .firstRun(home: URL(fileURLWithPath: "/nonexistent-home"), fileManager: .default),
                             coordinator: nil, calendarSync: nil)
        #expect(await model.projectDetail(first).visibleSpecs().isEmpty)
        model.setSpecOverride(projectId: first, specPath: path, .notDone, note: nil)
        #expect(await model.projectDetail(first).visibleSpecs().map(\.stage) == [.inProgress(done: 1, total: 1, external: 0)])
        #expect(await model.projectDetail(second).visibleSpecs().isEmpty)
        model.setSpecOverride(projectId: first, specPath: path, nil, note: nil)
        #expect(await model.projectDetail(first).visibleSpecs().isEmpty)
    }

    @Test func failedMarkSurfacesBannerAndLogWithoutPersistingOwnerText() async throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/sample", displayName: "Sample", identity: nil)
        let model = AppModel(store: store, settings: .firstRun(home: URL(fileURLWithPath: "/nonexistent-home"), fileManager: .default),
                             coordinator: nil, calendarSync: nil)
        var logs: [String] = []
        model.ownerErrorLog = { logs.append($0) }
        try await store.dbQueue.write { db in
            try db.execute(sql: "CREATE TRIGGER rejectMark BEFORE INSERT ON specOverride BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
        }
        model.setSpecOverride(projectId: id, specPath: "docs/sample.md", .done, note: "Private synthetic note")
        #expect(model.ownerDataError?.hasPrefix("Could not save the spec mark") == true)
        #expect(model.revision == 0)
        #expect(try store.specOverrides(projectId: id).isEmpty)
        #expect(logs.count == 1)
        #expect(logs.first?.hasPrefix("Could not save the spec mark:") == true)
        #expect(logs.first?.contains("code") == true)
        #expect(logs.allSatisfy { !$0.contains("Private synthetic note") && !$0.contains("INSERT") })
        _ = await model.projectDetail(id)
        #expect(model.ownerDataError != nil)
        try await store.dbQueue.write { try $0.execute(sql: "DROP TRIGGER rejectMark") }
        model.setSpecOverride(projectId: id, specPath: "docs/sample.md", .done, note: nil)
        #expect(model.ownerDataError == nil)
        #expect(logs.count == 1)
    }

    @Test func malformedSpecEvidenceSurfacesBannerAndLog() async throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/sample", displayName: "Sample", identity: nil)
        try await store.dbQueue.write { db in
            try db.execute(sql: "INSERT INTO specEvidence VALUES (?, 'docs/sample.md', 'invalid-json', 0)", arguments: [id])
        }
        let model = AppModel(store: store, settings: .firstRun(home: URL(fileURLWithPath: "/nonexistent-home"), fileManager: .default),
                             coordinator: nil, calendarSync: nil)
        var logs: [String] = []
        model.ownerErrorLog = { logs.append($0) }
        _ = await model.projectDetail(id)
        #expect(model.ownerDataError != nil)
        #expect(logs.count == 1)
        #expect(logs.first?.contains("invalid-json") == false)
    }
}
