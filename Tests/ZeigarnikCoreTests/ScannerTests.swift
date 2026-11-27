import Foundation
import Testing
@testable import ZeigarnikCore

/// Real git through ProcessRunner; `hc` answered from a canned payload.
private struct HcStubRunner: CommandRunning {
    let hcPath: String
    let hcOutput: Data
    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if executable == hcPath { return CommandResult(exitCode: 0, stdout: hcOutput, stderr: "", timedOut: false) }
        return await ProcessRunner().run(executable, arguments, cwd: cwd, environment: environment, timeout: timeout)
    }
}

/// Fails every `git log` call, so history is unavailable while other git calls work.
private struct FailingLogRunner: CommandRunning {
    let base: HcStubRunner
    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if arguments.contains("log") { return CommandResult(exitCode: 128, stdout: Data(), stderr: "fatal: synthetic log failure", timedOut: false) }
        return await base.run(executable, arguments, cwd: cwd, environment: environment, timeout: timeout)
    }
}

private struct World {
    let base: URL
    let root: URL
    let config: ScanConfig
    let store: Store
    let runner: HcStubRunner

    func write(_ url: URL, _ text: String, append: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
    }

    func scanner() -> ProjectScanner { makeTestScanner(config: config, store: store, runner: runner) }
}

private struct DiagnosticFailureRunner: CommandRunning {
    let base: HcStubRunner
    let command: String
    let stderr: String

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if arguments.last == "remote" { return CommandResult(exitCode: 0, stdout: Data("origin\n".utf8), stderr: "", timedOut: false) }
        if arguments.contains(command) { return CommandResult(exitCode: 128, stdout: Data(), stderr: stderr, timedOut: false) }
        return await base.run(executable, arguments, cwd: cwd, environment: environment, timeout: timeout)
    }
}

private final class RecordedScanLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanLog.Entry] = []
    var entries: [ScanLog.Entry] { lock.withLock { storage } }
    func append(_ entry: ScanLog.Entry) { lock.withLock { storage.append(entry) } }
}

private func json(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func claudeUser(_ session: String, _ cwd: String, _ ts: String, _ text: String = "Synthetic owner prompt.") -> String {
    json(["type": "user", "sessionId": session, "cwd": cwd, "timestamp": ts, "message": ["role": "user", "content": text]])
}

private func codexUser(_ ts: String, _ text: String = "Synthetic owner prompt.") -> String {
    json(["timestamp": ts, "type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]])
}

private func codexMeta(_ id: String, _ cwd: String, source: Any = "cli", originator: String = "codex-tui") -> String {
    json(["timestamp": "2026-11-18T10:00:00.000Z", "type": "session_meta", "payload": ["id": id, "timestamp": "2026-11-18T10:00:00.000Z", "cwd": cwd, "source": source, "originator": originator]])
}

private func makeWorld() async throws -> World {
    let base = try makeTempDir()
    let root = base.appendingPathComponent("Projects")
    let alpha = root.appendingPathComponent("02_Products/alpha")
    let beta = root.appendingPathComponent("beta")
    let gamma = root.appendingPathComponent("02_Products/gamma")
    let fm = FileManager.default
    for dir in [alpha, beta, gamma] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    for repo in [alpha, beta] {
        await runGit(repo, ["init", "-q"])
        try Data("# Repo\n\nA synthetic repository for scanner tests.\n".utf8).write(to: repo.appendingPathComponent("README.md"))
        await runGit(repo, ["add", "-A"])
        await runGit(repo, ["commit", "-q", "-m", "init"])
    }
    try Data("x".utf8).write(to: alpha.appendingPathComponent("untracked.txt"))
    let table = """
    # Projects

    ## Project Directories

    | Project | Directory | Vault Directory | Visibility |
    | ------- | --------- | --------------- | ---------- |
    | Alpha | `02_Products/alpha` | `03_Active_Projects/01_Private/alpha/` | Private |
    | Beta | `beta` | Not registered | Private |
    | Gamma | `02_Products/gamma` | Not registered | Private |
    """
    let vault = base.appendingPathComponent("vault")
    let claude = base.appendingPathComponent(".claude")
    let codex = base.appendingPathComponent(".codex")
    let world = World(
        base: base, root: root,
        config: ScanConfig(roots: [root], projectTableFile: root.appendingPathComponent("CLAUDE.md"), vaultRoot: vault,
                           claudeHome: claude, codexHome: codex, hcPath: "/fake/hc", home: base.path),
        store: try Store.inMemory(),
        runner: HcStubRunner(hcPath: "/fake/hc", hcOutput: Data(json(["terminals": [["address": "t1", "agent": "codex", "cwd": alpha.path, "status": "idle"]]]).utf8))
    )
    try world.write(root.appendingPathComponent("CLAUDE.md"), table)
    try world.write(vault.appendingPathComponent("03_Active_Projects/01_Private/alpha/tasks/Active Tasks.md"), "# Active Tasks\n\n- [ ] one\n- [ ] two\n- [x] done\n")
    // Claude: beta session c1 in history (2 prompts, 5 min apart) and in its transcript 240 ms off.
    try world.write(claude.appendingPathComponent("history.jsonl"), [
        json(["display": "Synthetic owner prompt.", "timestamp": 1_763_460_000_000.0, "project": beta.path, "sessionId": "c1", "pastedContents": [:]]),
        json(["display": "Synthetic owner prompt.", "timestamp": 1_763_460_300_000.0, "project": beta.path, "sessionId": "c1", "pastedContents": [:]]),
    ].joined(separator: "\n") + "\n")
    try world.write(claude.appendingPathComponent("projects/-beta/c1.jsonl"), [
        claudeUser("c1", beta.path, "2025-11-18T10:00:00.240Z"),
        claudeUser("c1", beta.path, "2025-11-18T10:05:00.240Z"),
    ].joined(separator: "\n") + "\n")
    // Codex: alpha session x1, two prompts 10 min apart, in both history and rollout; a delegated exec session in alpha.
    try world.write(codex.appendingPathComponent("sessions/2026/11/18/rollout-2026-11-18T10-00-00-x1.jsonl"), [
        codexMeta("x1", alpha.path), codexUser("2026-11-18T10:00:00.200Z"), codexUser("2026-11-18T10:10:00.200Z"),
    ].joined(separator: "\n") + "\n")
    try world.write(codex.appendingPathComponent("sessions/2026/11/18/rollout-2026-11-18T11-00-00-e1.jsonl"), [
        codexMeta("e1", alpha.path, source: "exec", originator: "codex_exec"), codexUser("2026-11-18T11:00:00.000Z"), codexUser("2026-11-18T11:05:00.000Z"),
    ].joined(separator: "\n") + "\n")
    try world.write(codex.appendingPathComponent("history.jsonl"), [
        json(["session_id": "x1", "ts": 1_763_460_000, "text": "Synthetic owner prompt."]),
        json(["session_id": "x1", "ts": 1_763_460_600, "text": "Synthetic owner prompt."]),
    ].joined(separator: "\n") + "\n")
    return world
}

@Suite("Scanner", .serialized)
struct ScannerTests {
    private let today = dayKey(Date(), calendar: .current)

    @Test func finishedScansLogEachErrorOnceAndOneSummary() async throws {
        let world = try await makeWorld()
        let output = RecordedScanLog()
        let runner = DiagnosticFailureRunner(base: world.runner, command: "worktree", stderr: "fatal: https://user:fake-token@host.example/repo")
        let scanner = makeTestScanner(config: world.config, store: world.store, runner: runner, log: ScanLog(emit: output.append))
        for _ in 0..<2 {
            let before = output.entries.count
            let report = await scanner.scan(fetch: false)
            #expect(report.errors.count == 2)
            let emitted = Array(output.entries.dropFirst(before))
            let expected: [ScanLog.Entry] = report.errors.map {
                .error(folder: URL(fileURLWithPath: $0.projectPath!).lastPathComponent, path: $0.projectPath!, message: "git worktree list --porcelain: fatal: https://<redacted>@host.example/repo")
            } + [.summary(projects: report.projects, errors: 2, duration: report.finishedAt.timeIntervalSince(report.startedAt))]
            #expect(emitted == expected)
        }
    }

    @Test func successfulScanLogsOnlySummary() async throws {
        let world = try await makeWorld()
        let output = RecordedScanLog()
        let report = await makeTestScanner(config: world.config, store: world.store, runner: world.runner, log: ScanLog(emit: output.append)).scan(fetch: false)
        #expect(report.errors.isEmpty)
        #expect(output.entries == [.summary(projects: 3, errors: 0, duration: report.finishedAt.timeIntervalSince(report.startedAt))])
    }

    @Test func fetchGuidanceReachesReportStoreAndCLI() async throws {
        let world = try await makeWorld()
        let raw = "fatal: Authentication failed for 'https://user:fake-token@host.example/repo'; retry"
        let runner = DiagnosticFailureRunner(base: world.runner, command: "fetch", stderr: raw)
        let report = await makeTestScanner(config: world.config, store: world.store, runner: runner).scan(fetch: true)
        let expected = "fetch: needs authentication. The remote uses HTTPS and git has no stored credential, so use an SSH remote or a credential helper. (git: fatal: Authentication failed for 'https://<redacted>@host.example/repo', retry)"
        #expect(report.errors.count == 2)
        #expect(report.errors.allSatisfy { $0.message == expected })
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(rows.filter { $0.displayName != "Gamma" }.allSatisfy { $0.error == expected })
        let table = formatProjectTable(rows, errors: report.errors, calendar: .current)
        #expect(table.contains(expected))
        #expect(!table.contains("fake-token"))
        let fetch = await GitInspector(runner: runner).fetch(world.root.appendingPathComponent("beta"))
        #expect(fetch == .failed("fatal: Authentication failed for 'https://<redacted>@host.example/repo'; retry"))
    }

    @Test func scanFromEntryPoint() async throws {
        let world = try await makeWorld()
        let report = await world.scanner().scan(fetch: false)
        #expect(report.errors.isEmpty, "\(report.errors)")
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(rows.map(\.displayName) == ["Alpha", "Beta", "Gamma"])
        let alpha = try #require(rows.first { $0.displayName == "Alpha" })
        #expect(alpha.status?.untracked == 1)
        #expect(alpha.totalSeconds == 600)
        #expect(alpha.lastActivityAgent == .codex)
        #expect(alpha.activeTasksOpen == 2)
        #expect(alpha.summary == "A synthetic repository for scanner tests.")
        #expect(alpha.readme == .current)
        #expect(report.openNow == .known([.project(alpha.id)]))
    }

    @Test func C5_fetchPoolRefillsBeforeSlowestRepoFinishes() async throws {
        let world = try await makeWorld()
        await runGit(world.root.appendingPathComponent("02_Products/gamma"), ["init", "-q"])
        var config = world.config
        config.fetchConcurrency = 2
        let runner = StaggeredFetchRunner(base: world.runner)
        _ = await makeTestScanner(config: config, store: world.store, runner: runner).scan(fetch: true)
        let events = await runner.events
        let thirdStart = try #require(events.firstIndex(of: "start3"))
        let firstFinish = try #require(events.firstIndex(of: "end1"))
        #expect(thirdStart < firstFinish)
        #expect(await runner.peak == 2)
        #expect(events.filter { $0.hasPrefix("start") }.count == 3)
    }

    @Test func historyWinsOverTranscriptForSameSession() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let beta = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        #expect(beta.totalSeconds == 300)
        #expect(beta.lastActivityAgent == .claude)
    }

    @Test func C9_scanNeverPersistsMessageTextIncludingWAL() async throws {
        let world = try await makeWorld()
        let marker = "SYNTHETIC_PRIVATE_PROMPT_" + UUID().uuidString
        let paths = [
            ".claude/history.jsonl", ".claude/projects/-beta/c1.jsonl",
            ".codex/history.jsonl", ".codex/sessions/2026/11/18/rollout-2026-11-18T10-00-00-x1.jsonl",
        ]
        for path in paths {
            let url = world.base.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: "Synthetic owner prompt.", with: marker)
            #expect(text.contains(marker))
            try world.write(url, text)
        }
        let dbURL = world.base.appendingPathComponent("privacy.sqlite")
        let store = try Store(path: dbURL.path)
        let report = await makeTestScanner(config: world.config, store: store, runner: world.runner).scan(fetch: false)
        #expect(report.errors.isEmpty)
        #expect(try store.messageCount() == 8)
        let messages = try store.effectiveMessages()
        #expect(messages.filter { $0.message.agent == .claude }.count == 2)
        #expect(messages.filter { $0.message.agent == .codex }.count == 2)
        let markerBytes = Data(marker.utf8)
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        #expect(try Data(contentsOf: walURL).count > 0)
        for suffix in ["", "-wal", "-shm"] {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: dbURL.path + suffix))
            #expect(bytes.range(of: markerBytes) == nil)
        }
        try store.checkpoint()
        #expect(try Data(contentsOf: dbURL).range(of: markerBytes) == nil)
    }

    @Test func tableProjectWithoutGitIsListed() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let gamma = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Gamma" })
        #expect(gamma.status == nil)
        #expect(gamma.state == .active)
    }

    @Test func C3_sharedNotesHonorStoredNotDoneOverride() async throws {
        let world = try await makeWorld()
        let path = "SHARED_TASK_NOTES.md"
        try world.write(world.root.appendingPathComponent("beta/" + path), "# Orbit notes\n- [x] Synthetic task\n")
        _ = await world.scanner().scan(fetch: false)
        let before = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        #expect(before.spec?.lastDone?.stage == .done)
        try world.store.setSpecOverride(projectId: before.id, specPath: path, .notDone, note: nil)
        _ = await world.scanner().scan(fetch: false)
        let after = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.id == before.id })
        #expect(after.spec?.current?.stage == .inProgress(done: 1, total: 1, external: 0))
        #expect(after.spec?.lastDone == nil)
    }

    @Test func rescanIngestsOnlyAppendedLines() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let before = try world.store.messageCount()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        try world.write(world.base.appendingPathComponent(".claude/projects/-alpha/n1.jsonl"), claudeUser("n1", alpha.path, "2026-11-18T12:00:00.000Z") + "\n")
        _ = await world.scanner().scan(fetch: false)
        #expect(try world.store.messageCount() == before + 1)
        _ = await world.scanner().scan(fetch: false)
        #expect(try world.store.messageCount() == before + 1)
    }

    @Test func unreadableSourceIsReportedNotEmpty() async throws {
        let world = try await makeWorld()
        let codex = world.base.appendingPathComponent(".codex/sessions")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: codex.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path) }
        let report = await world.scanner().scan(fetch: false)
        #expect(report.errors.contains { $0.message.contains(".codex/sessions") })
    }

    /// Finder leaves .DS_Store files in folders it has shown; they are not dated session folders.
    @Test func finderFilesInCodexSessionFoldersAreNotErrors() async throws {
        let world = try await makeWorld()
        let sessions = world.base.appendingPathComponent(".codex/sessions")
        for folder in ["", "2026", "2026/11", "2026/11/18"] {
            try Data("synthetic".utf8).write(to: sessions.appendingPathComponent(folder).appendingPathComponent(".DS_Store"))
        }
        let report = await world.scanner().scan(fetch: false)
        #expect(!report.errors.contains { $0.message.contains(".DS_Store") || ($0.projectPath ?? "").contains(".DS_Store") })
    }

    @Test func movedRepoKeepsIdentityAcrossScans() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let beta = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        try FileManager.default.createDirectory(at: world.root.appendingPathComponent("04_Analyses"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: world.root.appendingPathComponent("beta"), to: world.root.appendingPathComponent("04_Analyses/beta-moved"))
        _ = await world.scanner().scan(fetch: false)
        let moved = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.id == beta.id })
        #expect(moved.path.hasSuffix("04_Analyses/beta-moved"))
        #expect(moved.state == .active)
    }

    @Test func C10_scanReportsRelinkOnceWithOldAndNewPaths() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let before = try #require(try world.store.knownProjects().first { $0.path.hasSuffix("/beta") })
        let destination = world.root.appendingPathComponent("harbor")
        try FileManager.default.moveItem(at: URL(fileURLWithPath: before.path), to: destination)
        let report = await world.scanner().scan(fetch: false)
        #expect(report.relinks == [ProjectRelink(projectId: before.id, fromPath: before.path, toPath: destination.path)])
        let decoded = try JSONDecoder().decode(ScanReport.self, from: JSONEncoder().encode(report))
        #expect(decoded.relinks == report.relinks)
        #expect(await world.scanner().scan(fetch: false).relinks.isEmpty)
    }

    @Test func C10_tableMembershipPersistsAndClearsWhenUnlisted() async throws {
        let world = try await makeWorld()
        let path = world.base.appendingPathComponent("membership.sqlite").path
        let store = try Store(path: path)
        _ = await makeTestScanner(config: world.config, store: store, runner: world.runner).scan(fetch: false)
        let reopened = try Store(path: path)
        let rows = try reopened.projectRows(today: today, gap: 900)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.isTableProject })
        #expect(rows.allSatisfy { $0.withPinned(true).isTableProject })
        try world.write(world.root.appendingPathComponent("CLAUDE.md"), "# Projects\n")
        _ = await makeTestScanner(config: world.config, store: reopened, runner: world.runner).scan(fetch: false)
        #expect(try reopened.projectRows(today: today, gap: 900).allSatisfy { !$0.isTableProject })
    }

    @Test func siblingWorktreeDirtAndActivityCountForMain() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        let sibling = world.root.appendingPathComponent("02_Products/alpha-wt")
        await runGit(alpha, ["worktree", "add", "-q", sibling.path, "-b", "wt"])
        try Data("y".utf8).write(to: sibling.appendingPathComponent("wt-untracked.txt"))
        try world.write(world.base.appendingPathComponent(".claude/projects/-alpha-wt/w1.jsonl"), [
            claudeUser("w1", sibling.path, "2026-11-18T13:00:00.000Z"), claudeUser("w1", sibling.path, "2026-11-18T13:10:00.000Z"),
        ].joined(separator: "\n") + "\n")
        _ = await world.scanner().scan(fetch: false)
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(!rows.contains { $0.path.hasSuffix("alpha-wt") })
        let row = try #require(rows.first { $0.displayName == "Alpha" })
        #expect(row.status?.untracked == 2)
        #expect(row.totalSeconds == 1200)
    }

    @Test func unreadableRootDoesNotMarkMissing() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        var broken = world.config
        broken.roots = [world.base.appendingPathComponent("nonexistent")]
        let report = await makeTestScanner(config: broken, store: world.store, runner: world.runner).scan(fetch: false)
        #expect(!report.errors.isEmpty)
        #expect(try world.store.knownProjects().allSatisfy { $0.state == .active })
    }

    @Test func firstScanCodexPrecedence() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let x1 = try world.store.effectiveMessages().filter { $0.message.agent == .codex && $0.message.sessionId == "x1" }
        #expect(x1.count == 2)
        #expect(x1.allSatisfy { $0.message.source == .history })
        #expect(try world.store.effectiveMessages().allSatisfy { $0.message.sessionId != "e1" })
    }

    @Test func oversizedCodexHeaderLineIsStillRead() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        let meta = json(["timestamp": "2026-11-18T12:00:00.000Z", "type": "session_meta",
                         "payload": ["id": "big", "timestamp": "2026-11-18T12:00:00.000Z", "cwd": alpha.path, "source": "cli",
                                     "originator": "codex-tui", "base_instructions": ["text": String(repeating: "x", count: 200_000)]]])
        try world.write(world.base.appendingPathComponent(".codex/sessions/2026/11/18/rollout-2026-11-18T12-00-00-big.jsonl"),
                        [meta, codexUser("2026-11-18T12:00:00.500Z")].joined(separator: "\n") + "\n")
        _ = await world.scanner().scan(fetch: false)
        #expect(try world.store.effectiveMessages().contains { $0.message.sessionId == "big" })
    }

    @Test func movedRepoKeepsActivityAcrossScans() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let before = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        #expect(before.totalSeconds == 300)
        try FileManager.default.createDirectory(at: world.root.appendingPathComponent("04_Analyses"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: world.root.appendingPathComponent("beta"), to: world.root.appendingPathComponent("04_Analyses/beta-moved"))
        _ = await world.scanner().scan(fetch: false)
        let after = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.id == before.id })
        #expect(after.totalSeconds == 300)
    }

    @Test func twoCandidatesForOneMissingProjectAreAmbiguous() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let beta = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        let analyses = world.root.appendingPathComponent("04_Analyses")
        try FileManager.default.createDirectory(at: analyses, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: world.root.appendingPathComponent("beta"), to: analyses.appendingPathComponent("beta-moved"))
        try FileManager.default.copyItem(at: analyses.appendingPathComponent("beta-moved"), to: analyses.appendingPathComponent("beta-copy"))
        let report = await world.scanner().scan(fetch: false)
        let rows = try world.store.projectRows(today: today, gap: 900)
        let moved = try #require(rows.first { $0.path.hasSuffix("04_Analyses/beta-moved") })
        let copy = try #require(rows.first { $0.path.hasSuffix("04_Analyses/beta-copy") })
        #expect(moved.id != beta.id)
        #expect(copy.id != beta.id)
        #expect(moved.id != copy.id)
        #expect(report.errors.contains { $0.message.contains("Ambiguous") })
    }

    @Test func smallIngestBatchesIngestEverything() async throws {
        let world = try await makeWorld()
        var config = world.config
        config.ingestBatchBytes = 64
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner).scan(fetch: false)
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(rows.first { $0.displayName == "Alpha" }?.totalSeconds == 600)
        #expect(rows.first { $0.displayName == "Beta" }?.totalSeconds == 300)
    }

    @Test func unlistableSubdirectoryDoesNotMarkMissing() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let products = world.root.appendingPathComponent("02_Products")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: products.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: products.path) }
        let report = await world.scanner().scan(fetch: false)
        #expect(!report.errors.isEmpty)
        #expect(try world.store.knownProjects().allSatisfy { $0.state == .active })
    }

    @Test func architectureDocumentReachesTheRow() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        try world.write(alpha.appendingPathComponent("architecture.md"), "# Architecture\n")
        await runGit(alpha, ["add", "-A"])
        await runGit(alpha, ["commit", "-q", "-m", "doc"])
        try world.write(alpha.appendingPathComponent("Sources/Sync/engine.swift"), "let x = 1\n")
        await runGit(alpha, ["add", "Sources"])
        await runGit(alpha, ["commit", "-q", "-m", "sync"])
        _ = await world.scanner().scan(fetch: false)
        let row = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Alpha" })
        guard case .behind(let path, _, let since, let dirs, _, _)? = row.architecture else {
            Issue.record("expected behind, got \(String(describing: row.architecture))")
            return
        }
        #expect(path == "architecture.md")
        #expect(since == 1)
        #expect(dirs == ["Sources/Sync"])
        let beta = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Beta" })
        #expect(beta.architecture == ArchitectureDoc.none)
    }

    @Test func absentProjectTableIsNotAnErrorAndStillMarksMissing() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let ids = Dictionary(uniqueKeysWithValues: try world.store.projectRows(today: today, gap: 900).map { ($0.displayName, $0.id) })
        try FileManager.default.removeItem(at: world.root.appendingPathComponent("CLAUDE.md"))
        try FileManager.default.removeItem(at: world.root.appendingPathComponent("beta"))
        let report = await world.scanner().scan(fetch: false)
        #expect(report.errors.isEmpty, "\(report.errors)")
        let states = Dictionary(uniqueKeysWithValues: try world.store.projectRows(today: today, gap: 900).map { ($0.id, $0.state) })
        #expect(states[try #require(ids["Alpha"])] == .active)
        #expect(states[try #require(ids["Beta"])] == .missing)
    }

    @Test func unreadableProjectTableDoesNotMarkMissing() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let table = world.root.appendingPathComponent("CLAUDE.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: table.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: table.path) }
        let report = await world.scanner().scan(fetch: false)
        #expect(!report.errors.isEmpty)
        #expect(try world.store.knownProjects().allSatisfy { $0.state == .active })
    }

    @Test func failedHistoryKeepsCommitDaysAndLeavesReadmeUnknown() async throws {
        let world = try await makeWorld()
        _ = await world.scanner().scan(fetch: false)
        let alpha = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.displayName == "Alpha" })
        #expect(try world.store.commitDayCount(projectId: alpha.id) == 1)
        let report = await makeTestScanner(config: world.config, store: world.store, runner: FailingLogRunner(base: world.runner)).scan(fetch: false)
        #expect(report.errors.contains { $0.message.contains("history") })
        #expect(try world.store.commitDayCount(projectId: alpha.id) == 1)
        let after = try #require(try world.store.projectRows(today: today, gap: 900).first { $0.id == alpha.id })
        #expect(after.readme == nil)
    }

    @Test func symlinkedRootDoesNotDuplicateOrDoubleCount() async throws {
        let world = try await makeWorld()
        let link = world.base.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: world.root)
        var config = world.config
        config.roots = [link]
        let report = await makeTestScanner(config: config, store: world.store, runner: world.runner).scan(fetch: false)
        #expect(report.errors.isEmpty, "\(report.errors)")
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(rows.map(\.displayName) == ["Alpha", "Beta", "Gamma"])
        #expect(rows.first { $0.displayName == "Alpha" }?.status?.untracked == 1)
    }

    @Test func visibilityIsAskedOncePerDayForProjectsWithAKnownRemote() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        await runGit(alpha, ["remote", "add", "origin", "git@github.com:acme/alpha.git"])
        let probe = CountingProbe(answer: .public)
        var config = world.config
        config.checkVisibility = true
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(await probe.asked.items == [RemoteRepo(host: "github.com", path: "acme/alpha")])
        let rows = try world.store.projectRows(today: today, gap: 900)
        #expect(rows.first { $0.displayName == "Alpha" }?.visibility == .public)
        #expect(rows.first { $0.displayName == "Beta" }?.visibility == nil)
    }

    @Test func unknownVisibilityIsAskedAgainOnTheNextScan() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        await runGit(alpha, ["remote", "add", "origin", "https://github.com/acme/alpha.git"])
        let probe = CountingProbe(answer: .unknown)
        var config = world.config
        config.checkVisibility = true
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(await probe.asked.items.count == 2)
    }

    @Test func visibilityCheckOffAsksNothing() async throws {
        let world = try await makeWorld()
        let alpha = world.root.appendingPathComponent("02_Products/alpha")
        await runGit(alpha, ["remote", "add", "origin", "git@github.com:acme/alpha.git"])
        let probe = CountingProbe(answer: .public)
        _ = await makeTestScanner(config: world.config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(await probe.asked.items.isEmpty)
        #expect(try world.store.projectRows(today: today, gap: 900).allSatisfy { $0.visibility == nil })
    }

    @Test func C13_transientRemoteFailurePreservesVisibilityAndIdentity() async throws {
        let world = try await makeWorld()
        let repo = world.root.appendingPathComponent("beta")
        await runGit(repo, ["remote", "add", "origin", "https://github.com/orbit/lumen.git"])
        var config = world.config
        config.checkVisibility = true
        let probe = CountingProbe(answer: .public)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        let before = try #require(try world.store.knownProjects().first { $0.path == repo.path })
        _ = await makeTestScanner(config: config, store: world.store, runner: FailingRemoteRunner(base: world.runner), visibilityProbe: probe).scan(fetch: false)
        #expect(try world.store.visibilityChecks()[before.id]?.visibility == .public)
        #expect(try world.store.knownProjects().first { $0.id == before.id }?.identity?.remoteURL == before.identity?.remoteURL)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(await probe.asked.items.count == 1)
    }

    @Test func C13_definiteRemoteChangeInvalidatesEvenWithProbeDisabled() async throws {
        let world = try await makeWorld()
        let repo = world.root.appendingPathComponent("beta")
        await runGit(repo, ["remote", "add", "origin", "https://github.com/orbit/lumen.git"])
        var config = world.config
        config.checkVisibility = true
        let probe = CountingProbe(answer: .public)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        let id = try #require(try world.store.knownProjects().first { $0.path == repo.path }?.id)
        await runGit(repo, ["remote", "set-url", "origin", "https://github.com/orbit/harbor.git"])
        config.checkVisibility = false
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(try world.store.visibilityChecks()[id] == nil)
        config.checkVisibility = true
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(await probe.asked.items == [RemoteRepo(host: "github.com", path: "orbit/lumen"), RemoteRepo(host: "github.com", path: "orbit/harbor")])
        await runGit(repo, ["remote", "remove", "origin"])
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(try world.store.visibilityChecks()[id] == nil)
    }

    @Test func C13_missingRepoDropsCachedVisibility() async throws {
        let world = try await makeWorld()
        let repo = world.root.appendingPathComponent("beta")
        await runGit(repo, ["remote", "add", "origin", "https://github.com/orbit/lumen.git"])
        var config = world.config
        config.checkVisibility = true
        let probe = CountingProbe(answer: .public)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        let id = try #require(try world.store.knownProjects().first { $0.path == repo.path }?.id)
        try FileManager.default.removeItem(at: repo)
        _ = await makeTestScanner(config: config, store: world.store, runner: world.runner, visibilityProbe: probe).scan(fetch: false)
        #expect(try world.store.visibilityChecks()[id] == nil)
        #expect(try world.store.knownProjects().first { $0.id == id }?.state == .missing)
    }
}

private struct FailingRemoteRunner: CommandRunning {
    let base: HcStubRunner

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if arguments.contains("config") && arguments.contains("remote.origin.url") {
            return CommandResult(exitCode: 128, stdout: Data(), stderr: "Synthetic transient failure", timedOut: false)
        }
        return await base.run(executable, arguments, cwd: cwd, environment: environment, timeout: timeout)
    }
}

private struct CountingProbe: VisibilityProbing {
    let answer: RepoVisibility
    let asked = Recorder<RemoteRepo>()
    func visibility(of repo: RemoteRepo) async -> RepoVisibility {
        await asked.add(repo)
        return answer
    }
}

private actor StaggeredFetchRunner: CommandRunning {
    let base: HcStubRunner
    var events: [String] = []
    var peak = 0
    private var started = 0
    private var active = 0
    private var held: CheckedContinuation<Void, Never>?

    init(base: HcStubRunner) { self.base = base }

    private func releaseFirst() { held?.resume(); held = nil }

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if arguments.last == "remote" { return CommandResult(exitCode: 0, stdout: Data("origin\n".utf8), stderr: "", timedOut: false) }
        guard arguments.contains("fetch") else {
            return await base.run(executable, arguments, cwd: cwd, environment: environment, timeout: timeout)
        }
        started += 1
        let index = started
        active += 1
        peak = max(peak, active)
        events.append("start\(index)")
        if index == 1 {
            let fallback = Task {
                try? await Task.sleep(for: .seconds(2))
                releaseFirst()
            }
            await withCheckedContinuation { held = $0 }
            fallback.cancel()
        } else {
            if index == 3 { releaseFirst() }
            try? await Task.sleep(for: .milliseconds(10))
        }
        active -= 1
        events.append("end\(index)")
        return CommandResult(exitCode: 0, stdout: Data(), stderr: "", timedOut: false)
    }
}
