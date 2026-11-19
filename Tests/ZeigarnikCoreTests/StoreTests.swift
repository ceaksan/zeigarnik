import Foundation
import Testing
import GRDB
@testable import ZeigarnikCore

private func identity(_ roots: Set<String>, remote: String? = "https://example.com/r.git", dir: String = "/x/.git") -> GitIdentity {
    GitIdentity(commonDir: dir, rootCommits: roots, remoteURL: remote)
}

@Suite("Identity")
struct IdentityTests {
    @Test func samePathIsExisting() {
        let known = [KnownProject(id: "a", path: "/r/a", state: .active, identity: identity(["r1"]))]
        #expect(resolveIdentity(path: "/r/a", identity: identity(["r1"]), known: known, pathExists: { _ in true }) == .existing("a"))
    }

    @Test func movedRepoWithUniqueMatchIsRelinked() {
        let known = [KnownProject(id: "a", path: "/old", state: .active, identity: identity(["r1"]))]
        #expect(resolveIdentity(path: "/new", identity: identity(["r1"]), known: known, pathExists: { $0 != "/old" }) == .relinked("a", fromPath: "/old"))
    }

    @Test func existingPathIsNotARelinkCandidate() {
        let known = [KnownProject(id: "a", path: "/old", state: .active, identity: identity(["r1"]))]
        #expect(resolveIdentity(path: "/clone", identity: identity(["r1"]), known: known, pathExists: { _ in true }) == .new)
    }

    @Test func cloneWithMultipleCandidatesIsAmbiguous() {
        let known = [
            KnownProject(id: "a", path: "/gone1", state: .missing, identity: identity(["r1"])),
            KnownProject(id: "b", path: "/gone2", state: .missing, identity: identity(["r1"])),
        ]
        #expect(resolveIdentity(path: "/new", identity: identity(["r1"]), known: known, pathExists: { _ in false }) == .ambiguous(["a", "b"]))
    }

    @Test func multipleRootCommitsMatchOnIntersection() {
        let known = [KnownProject(id: "a", path: "/old", state: .missing, identity: identity(["r1", "r2"]))]
        #expect(resolveIdentity(path: "/new", identity: identity(["r2"]), known: known, pathExists: { _ in false }) == .relinked("a", fromPath: "/old"))
    }

    @Test func differentRemoteIsNotAMatch() {
        let known = [KnownProject(id: "a", path: "/old", state: .missing, identity: identity(["r1"], remote: "https://example.com/other.git"))]
        #expect(resolveIdentity(path: "/new", identity: identity(["r1"]), known: known, pathExists: { _ in false }) == .new)
    }

    @Test func unbornRepoMatchesOnlyByPath() {
        let known = [KnownProject(id: "a", path: "/old", state: .missing, identity: identity([]))]
        #expect(resolveIdentity(path: "/new", identity: identity([]), known: known, pathExists: { _ in false }) == .new)
    }
}

@Suite("Store")
struct StoreTests {
    private let day = "2026-11-18"

    private func msg(_ session: String, _ iso: String, cwd: String? = "/r/a", agent: Agent = .claude, source: MessageSource = .transcript) -> OwnerMessage {
        OwnerMessage(agent: agent, sessionId: session, timestamp: isoDate(iso), cwd: cwd, source: source)
    }

    private func seeded() throws -> (Store, String) {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/a", displayName: "Alpha", identity: identity(["r1"]))
        return (store, id)
    }

    private func mapper(_ id: String) -> ProjectMapper {
        ProjectMapper(projects: [(id: id, path: "/r/a")], home: "/Users/u", workspaceRoot: "/r")
    }

    @Test func ingestIsAtomic() throws {
        let (store, _) = try seeded()
        let good = msg("s", "2026-11-18T10:00:00Z")
        let cursor = FileCursor(inode: 1, size: 10, offset: 10, headLength: 10, headHash: "h")
        let bad = SessionObservation(agent: .claude, sessionId: "", cwd: nil, firstSeen: nil, lastSeen: nil, delegated: false)
        #expect(throws: (any Error).self) {
            try store.ingest(IngestBatch(messages: [good], sessions: [bad], codexHeaders: [], cursor: (path: "/f.jsonl", cursor: cursor)))
        }
        #expect(try store.cursor(for: "/f.jsonl") == nil)
        #expect(try store.messageCount() == 0)
    }

    @Test func duplicateMessagesAreIgnored() throws {
        let (store, _) = try seeded()
        let m = msg("s", "2026-11-18T10:00:00Z")
        try store.ingest(IngestBatch(messages: [m], sessions: [], codexHeaders: [], cursor: nil))
        try store.ingest(IngestBatch(messages: [m], sessions: [], codexHeaders: [], cursor: nil))
        #expect(try store.messageCount() == 1)
    }

    @Test func cursorRoundTrips() throws {
        let (store, _) = try seeded()
        let cursor = FileCursor(inode: 7, size: 20, offset: 18, headLength: 20, headHash: "abc")
        try store.ingest(IngestBatch(messages: [], sessions: [], codexHeaders: [], cursor: (path: "/f.jsonl", cursor: cursor)))
        #expect(try store.cursor(for: "/f.jsonl") == cursor)
    }

    @Test func snapshotUpsertsPerDay() throws {
        let (store, id) = try seeded()
        func snap(_ untracked: Int) -> ProjectSnapshot {
            ProjectSnapshot(projectId: id, day: day, scannedAt: Date(), status: GitStatus(branch: "main", upstream: nil, ahead: nil, behind: nil, changed: 0, untracked: untracked, stash: 0),
                            fetch: nil, lastFetchAt: nil, lastCommitAt: nil, readme: .current, spec: SpecHeadline(current: nil, lastDone: nil), activeTasksOpen: nil, error: nil)
        }
        try store.writeSnapshot(snap(1))
        try store.writeSnapshot(snap(5))
        #expect(try store.snapshotCount() == 1)
        #expect(try store.projectRows(today: day, gap: 900).first?.status?.untracked == 5)
    }

    @Test func projectRowsTotalsUseUnion() throws {
        let (store, id) = try seeded()
        let messages = [
            msg("A", "2026-11-18T10:00:00Z"), msg("A", "2026-11-18T10:10:00Z"), msg("A", "2026-11-18T10:20:00Z"),
            msg("B", "2026-11-18T10:05:00Z"), msg("B", "2026-11-18T10:15:00Z"), msg("B", "2026-11-18T10:25:00Z"),
        ]
        try store.ingest(IngestBatch(messages: messages, sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 1500)
    }

    @Test func historySupersedesTranscriptAcrossRescans() throws {
        let (store, id) = try seeded()
        try store.ingest(IngestBatch(messages: [msg("S", "2026-11-18T10:00:00Z"), msg("S", "2026-11-18T10:10:00Z")], sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 600)
        try store.ingest(IngestBatch(messages: [msg("S", "2026-11-18T10:00:00.240Z", source: .history), msg("S", "2026-11-18T10:05:00Z", source: .history)], sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        let total = try #require(try store.projectRows(today: day, gap: 900).first?.totalSeconds)
        #expect(abs(total - 299.76) < 0.01)
    }

    @Test func codexHistoryBeforeRolloutHeader() throws {
        let (store, id) = try seeded()
        let history = [msg("cx", "2026-11-18T10:00:00Z", cwd: nil, agent: .codex, source: .history), msg("cx", "2026-11-18T10:10:00Z", cwd: nil, agent: .codex, source: .history)]
        try store.ingest(IngestBatch(messages: history, sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 0)
        try store.ingest(IngestBatch(messages: [], sessions: [], codexHeaders: [CodexSessionHeader(sessionId: "cx", cwd: "/r/a/sub", isDelegated: false, startedAt: nil)], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        let row = try #require(try store.projectRows(today: day, gap: 900).first)
        #expect(row.totalSeconds == 600)
        #expect(row.lastActivityAgent == .codex)
    }

    @Test func delegatedSessionNeverCounts() throws {
        let (store, id) = try seeded()
        let messages = [msg("d", "2026-11-18T10:00:00Z", agent: .codex), msg("d", "2026-11-18T10:10:00Z", agent: .codex)]
        try store.ingest(IngestBatch(messages: messages, sessions: [], codexHeaders: [CodexSessionHeader(sessionId: "d", cwd: "/r/a", isDelegated: true, startedAt: nil)], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 0)
    }

    @Test func untimedSessionIsVisible() throws {
        let (store, id) = try seeded()
        let observation = SessionObservation(agent: .claude, sessionId: "u", cwd: "/r/a", firstSeen: nil, lastSeen: nil, delegated: false)
        try store.ingest(IngestBatch(messages: [], sessions: [observation], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.sessionCount(projectId: id) == 1)
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 0)
    }

    @Test func gapReachesTotals() throws {
        let (store, id) = try seeded()
        try store.ingest(IngestBatch(messages: [msg("g", "2026-11-18T10:00:00Z"), msg("g", "2026-11-18T10:20:00Z")], sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        #expect(try store.projectRows(today: day, gap: 900).first?.totalSeconds == 0)
        #expect(try store.projectRows(today: day, gap: 1800).first?.totalSeconds == 1200)
    }

    @Test func relinkKeepsIdAndUpdatesPath() throws {
        let (store, id) = try seeded()
        let again = try store.upsertProject(resolution: .relinked(id, fromPath: "/r/a"), path: "/r/moved", displayName: "Alpha", identity: identity(["r1"]))
        #expect(again == id)
        #expect(try store.knownProjects().map(\.path) == ["/r/moved"])
    }

    @Test func markMissingOnlyUnderEnumeratedRoots() throws {
        let store = try Store.inMemory()
        let a = try store.upsertProject(resolution: .new, path: "/root1/a", displayName: "A", identity: nil)
        let b = try store.upsertProject(resolution: .new, path: "/root2/b", displayName: "B", identity: nil)
        try store.markMissing(exceptIds: [], underRoots: ["/root1"], currentRoots: ["/root1", "/root2"])
        let states = Dictionary(uniqueKeysWithValues: try store.knownProjects().map { ($0.id, $0.state) })
        #expect(states[a] == .missing)
        #expect(states[b] == .active)
    }

    @Test func projectsOfARemovedRootGoMissing() throws {
        let store = try Store.inMemory()
        let kept = try store.upsertProject(resolution: .new, path: "/root1/a", displayName: "A", identity: nil)
        let removed = try store.upsertProject(resolution: .new, path: "/tried/b", displayName: "B", identity: nil)
        let listed = try store.upsertProject(resolution: .new, path: "/elsewhere/c", displayName: "C", identity: nil)
        try store.markMissing(exceptIds: [kept, listed], underRoots: ["/root1"], currentRoots: ["/root1"])
        let states = Dictionary(uniqueKeysWithValues: try store.knownProjects().map { ($0.id, $0.state) })
        #expect(states[kept] == .active)
        #expect(states[removed] == .missing)
        #expect(states[listed] == .active)
        // Without the current roots (the CLI scans a subset of the shared database), nothing outside the scanned roots changes.
        let other = try store.upsertProject(resolution: .new, path: "/other/d", displayName: "D", identity: nil)
        try store.markMissing(exceptIds: [kept, listed], underRoots: ["/root1"], currentRoots: nil)
        #expect(try store.knownProjects().first { $0.id == other }?.state == .active)
    }

    @Test func noMessageTextOrCredentialsPersisted() throws {
        let dir = try makeTempDir()
        let path = dir.appendingPathComponent("zg.sqlite").path
        let store = try Store(path: path)
        let id = try store.upsertProject(resolution: .new, path: "/r/a", displayName: "Alpha", identity: identity(["r1"], remote: sanitizeRemoteURL("https://user:fake-token@gitlab.example.com/x.git")))
        var messages: [OwnerMessage] = []
        for line in fixtureLines("claude-transcript.jsonl") {
            if case .record(let m) = parseClaudeTranscriptLine(line) { messages.append(m) }
        }
        try store.ingest(IngestBatch(messages: messages, sessions: [], codexHeaders: [], cursor: nil))
        try store.reassignOwners(mapper: mapper(id))
        try store.checkpoint()
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(bytes.range(of: Data("Inspect the synthetic sample".utf8)) == nil)
        #expect(bytes.range(of: Data("fake-token".utf8)) == nil)
        #expect(bytes.range(of: Data("gitlab.example.com".utf8)) != nil)
    }
}
