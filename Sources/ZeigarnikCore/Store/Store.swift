import Foundation
import GRDB

public struct SessionObservation: Sendable, Equatable {
    public let agent: Agent
    public let sessionId: String
    public let cwd: String?
    public let firstSeen: Date?
    public let lastSeen: Date?
    public let delegated: Bool

    public init(agent: Agent, sessionId: String, cwd: String?, firstSeen: Date?, lastSeen: Date?, delegated: Bool) {
        self.agent = agent
        self.sessionId = sessionId
        self.cwd = cwd
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.delegated = delegated
    }
}

public struct IngestBatch: Sendable {
    public let messages: [OwnerMessage]
    public let sessions: [SessionObservation]
    public let codexHeaders: [CodexSessionHeader]
    public let cursor: (path: String, cursor: FileCursor)?

    public init(messages: [OwnerMessage], sessions: [SessionObservation], codexHeaders: [CodexSessionHeader], cursor: (path: String, cursor: FileCursor)?) {
        self.messages = messages
        self.sessions = sessions
        self.codexHeaders = codexHeaders
        self.cursor = cursor
    }
}

public struct ProjectSnapshot: Sendable, Equatable {
    public let projectId: String
    public let day: String
    public let scannedAt: Date
    public let status: GitStatus?
    public let fetch: FetchOutcome?
    public let lastFetchAt: Date?
    public let lastCommitAt: Date?
    /// nil when git history could not be read this scan (unknown, not current).
    public let readme: ReadmeDrift?
    /// nil when spec evidence could not be computed this scan; the day's earlier value is kept.
    public let spec: SpecHeadline?
    public let activeTasksOpen: Int?
    public let error: String?
    /// nil when git history could not be read this scan.
    public let architecture: ArchitectureDoc?

    public init(projectId: String, day: String, scannedAt: Date, status: GitStatus?, fetch: FetchOutcome?, lastFetchAt: Date?, lastCommitAt: Date?, readme: ReadmeDrift?, spec: SpecHeadline?, activeTasksOpen: Int?, error: String?, architecture: ArchitectureDoc? = nil) {
        self.architecture = architecture
        self.projectId = projectId
        self.day = day
        self.scannedAt = scannedAt
        self.status = status
        self.fetch = fetch
        self.lastFetchAt = lastFetchAt
        self.lastCommitAt = lastCommitAt
        self.readme = readme
        self.spec = spec
        self.activeTasksOpen = activeTasksOpen
        self.error = error
    }
}

public struct ProjectRow: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let summary: String?
    public let path: String
    public let state: ProjectState
    public let pinned: Bool
    public let lastActivityAt: Date?
    public let lastActivityAgent: Agent?
    public let lastCommitAt: Date?
    public let status: GitStatus?
    public let lastFetchAt: Date?
    public let readme: ReadmeDrift?
    public let spec: SpecHeadline?
    public let activeTasksOpen: Int?
    public let error: String?
    public let totalSeconds: TimeInterval
    public let architecture: ArchitectureDoc?
    public let visibility: RepoVisibility?
    public let isTableProject: Bool

    public init(id: String, displayName: String, summary: String?, path: String, state: ProjectState, pinned: Bool,
                lastActivityAt: Date?, lastActivityAgent: Agent?, lastCommitAt: Date?, status: GitStatus?, lastFetchAt: Date?,
                readme: ReadmeDrift?, spec: SpecHeadline?, activeTasksOpen: Int?, error: String?, totalSeconds: TimeInterval,
                architecture: ArchitectureDoc? = nil, visibility: RepoVisibility? = nil, isTableProject: Bool = false) {
        self.isTableProject = isTableProject
        self.architecture = architecture
        self.visibility = visibility
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.path = path
        self.state = state
        self.pinned = pinned
        self.lastActivityAt = lastActivityAt
        self.lastActivityAgent = lastActivityAgent
        self.lastCommitAt = lastCommitAt
        self.status = status
        self.lastFetchAt = lastFetchAt
        self.readme = readme
        self.spec = spec
        self.activeTasksOpen = activeTasksOpen
        self.error = error
        self.totalSeconds = totalSeconds
    }

    /// A copy with every field kept; a memberwise rebuild once dropped fields that have defaults.
    public func withPinned(_ pinned: Bool) -> ProjectRow {
        ProjectRow(id: id, displayName: displayName, summary: summary, path: path, state: state, pinned: pinned,
                   lastActivityAt: lastActivityAt, lastActivityAgent: lastActivityAgent, lastCommitAt: lastCommitAt, status: status,
                   lastFetchAt: lastFetchAt, readme: readme, spec: spec, activeTasksOpen: activeTasksOpen, error: error,
                   totalSeconds: totalSeconds, architecture: architecture, visibility: visibility, isTableProject: isTableProject)
    }
}

public final class Store: Sendable {
    let dbQueue: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(5)
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try dbQueue.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        try Self.migrator.migrate(dbQueue)
    }

    init(queue: DatabaseQueue) throws {
        dbQueue = queue
        try Self.migrator.migrate(dbQueue)
    }

    public static func inMemory() throws -> Store {
        try Store(queue: try DatabaseQueue())
    }

    // MARK: Projects

    public func knownProjects() throws -> [KnownProject] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.id, p.path, p.state, i.commonDir, i.rootCommits, i.remoteURL
                FROM project p LEFT JOIN projectIdentity i ON i.projectId = p.id ORDER BY p.path
                """).map { row in
                let identity: GitIdentity? = (row["commonDir"] as String?).map { dir in
                    let roots = (row["rootCommits"] as String? ?? "").split(separator: ",").map(String.init)
                    return GitIdentity(commonDir: dir, rootCommits: Set(roots), remoteURL: row["remoteURL"])
                }
                return KnownProject(id: row["id"], path: row["path"], state: ProjectState(rawValue: row["state"]) ?? .active, identity: identity)
            }
        }
    }

    public func upsertProject(resolution: IdentityResolution, path: String, displayName: String, identity: GitIdentity?) throws -> String {
        try dbQueue.write { db in
            let now = Date().timeIntervalSince1970
            let id: String
            switch resolution {
            case .existing(let existing), .relinked(let existing, _):
                id = existing
                try db.execute(sql: "UPDATE project SET path = ?, displayName = ?, state = 'active', lastSeenAt = ? WHERE id = ?",
                               arguments: [path, displayName, now, id])
            case .new, .ambiguous:
                id = UUID().uuidString
                try db.execute(sql: "INSERT INTO project (id, displayName, path, state, createdAt, lastSeenAt) VALUES (?, ?, ?, 'active', ?, ?)",
                               arguments: [id, displayName, path, now, now])
            }
            if let identity {
                let previousRemote = try String.fetchOne(db, sql: "SELECT remoteURL FROM projectIdentity WHERE projectId = ?", arguments: [id])
                let remote = identity.remoteResolved ? identity.remoteURL.map(sanitizeRemoteURL) : previousRemote
                if identity.remoteResolved && previousRemote != remote {
                    try db.execute(sql: "DELETE FROM repoVisibility WHERE projectId = ?", arguments: [id])
                }
                try db.execute(sql: """
                    INSERT INTO projectIdentity (projectId, commonDir, rootCommits, remoteURL) VALUES (?, ?, ?, ?)
                    ON CONFLICT(projectId) DO UPDATE SET commonDir = excluded.commonDir, rootCommits = excluded.rootCommits, remoteURL = excluded.remoteURL
                    """, arguments: [id, identity.commonDir, identity.rootCommits.sorted().joined(separator: ","), remote])
            } else {
                try db.execute(sql: "DELETE FROM projectIdentity WHERE projectId = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM repoVisibility WHERE projectId = ?", arguments: [id])
            }
            return id
        }
    }

    /// Remembers every path a project has been seen at, so activity under old paths still maps to it.
    public func recordPaths(projectId: String, _ paths: [String]) throws {
        try dbQueue.write { db in
            for path in paths {
                try db.execute(sql: "INSERT OR IGNORE INTO projectPath (projectId, path) VALUES (?, ?)", arguments: [projectId, path])
            }
        }
    }

    public func projectPaths() throws -> [(id: String, path: String)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT projectId, path FROM projectPath ORDER BY projectId, path").map { (id: $0["projectId"], path: $0["path"]) }
        }
    }

    /// `currentRoots`: every configured root, or nil when the caller scans only part of the shared database (the CLI).
    public func markMissing(exceptIds: Set<String>, underRoots: [String], currentRoots: [String]?) throws {
        try dbQueue.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, path FROM project")
            for row in rows {
                let id: String = row["id"]
                let path: String = row["path"]
                let inside = { (roots: [String]) in roots.contains(where: { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) }
                // Not seen this scan: missing when its root was fully read, or when no current root holds it (a removed folder).
                // A root that could not be read completely proves nothing, so its projects stay as they are.
                let removedRoot = currentRoots.map { !inside($0) } ?? false
                guard !exceptIds.contains(id), inside(underRoots) || removedRoot else { continue }
                try db.execute(sql: "UPDATE project SET state = 'missing' WHERE id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM repoVisibility WHERE projectId = ?", arguments: [id])
            }
        }
    }

    public func updateSummary(projectId: String, _ summary: String?) throws {
        try dbQueue.write { db in try db.execute(sql: "UPDATE project SET summary = ? WHERE id = ?", arguments: [summary, projectId]) }
    }

    public func updateTableMembership(projectIds: Set<String>, tablePath: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE project SET projectTablePath = NULL WHERE projectTablePath = ?", arguments: [tablePath])
            for id in projectIds {
                try db.execute(sql: "UPDATE project SET projectTablePath = ? WHERE id = ?", arguments: [tablePath, id])
            }
        }
    }

    // MARK: Snapshots and per-scan facts

    public func writeSnapshot(_ s: ProjectSnapshot) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO snapshot (projectId, day, scannedAt, status, fetch, lastFetchAt, lastCommitAt, readme, spec, activeTasksOpen, error, architecture)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(projectId, day) DO UPDATE SET scannedAt = excluded.scannedAt, status = excluded.status, fetch = excluded.fetch,
                  lastFetchAt = COALESCE(excluded.lastFetchAt, snapshot.lastFetchAt), lastCommitAt = COALESCE(excluded.lastCommitAt, snapshot.lastCommitAt), readme = excluded.readme,
                  spec = COALESCE(excluded.spec, snapshot.spec), activeTasksOpen = excluded.activeTasksOpen, error = excluded.error,
                  architecture = excluded.architecture
                """, arguments: [s.projectId, s.day, s.scannedAt.timeIntervalSince1970, try json(s.status), try json(s.fetch),
                                 s.lastFetchAt?.timeIntervalSince1970, s.lastCommitAt?.timeIntervalSince1970, try json(s.readme),
                                 try json(s.spec), s.activeTasksOpen, s.error, try json(s.architecture)])
        }
    }

    /// Last successful fetch recorded for a project on any day, so a failed fetch today keeps showing it.
    public func lastFetchAt(projectId: String) throws -> Date? {
        try dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT MAX(lastFetchAt) FROM snapshot WHERE projectId = ?", arguments: [projectId])
                .map { Date(timeIntervalSince1970: $0) }
        }
    }

    public func replaceCommitDays(projectId: String, _ days: [String: Int]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM commitDay WHERE projectId = ?", arguments: [projectId])
            for (day, count) in days {
                try db.execute(sql: "INSERT INTO commitDay (projectId, day, count) VALUES (?, ?, ?)", arguments: [projectId, day, count])
            }
        }
    }

    public func replaceSpecEvidence(projectId: String, _ specs: [SpecSummary]) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM specEvidence WHERE projectId = ?", arguments: [projectId])
            let now = Date().timeIntervalSince1970
            for spec in specs {
                try db.execute(sql: "INSERT INTO specEvidence (projectId, specPath, json, scannedAt) VALUES (?, ?, ?, ?)",
                               arguments: [projectId, spec.specPath, try json(spec), now])
            }
        }
    }

    public func specOverrides(projectId: String) throws -> [String: OwnerSpecOverride] {
        try dbQueue.read { db in
            var result: [String: OwnerSpecOverride] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT specPath, state FROM specOverride WHERE projectId = ?", arguments: [projectId]) {
                if let state = OwnerSpecOverride(rawValue: row["state"]) { result[row["specPath"]] = state }
            }
            return result
        }
    }

    // MARK: Activity

    public func ingest(_ batch: IngestBatch) throws {
        try dbQueue.write { db in
            for m in batch.messages {
                try db.execute(sql: "INSERT OR IGNORE INTO ownerMessage (agent, sessionId, ts, cwd, source) VALUES (?, ?, ?, ?, ?)",
                               arguments: [m.agent.rawValue, m.sessionId, m.timestamp.timeIntervalSince1970, m.cwd, m.source.rawValue])
            }
            for s in batch.sessions {
                try db.execute(sql: """
                    INSERT INTO session (agent, sessionId, cwd, firstSeen, lastSeen, delegated) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(agent, sessionId) DO UPDATE SET
                      cwd = COALESCE(session.cwd, excluded.cwd),
                      firstSeen = CASE WHEN session.firstSeen IS NULL OR excluded.firstSeen < session.firstSeen THEN COALESCE(excluded.firstSeen, session.firstSeen) ELSE session.firstSeen END,
                      lastSeen = CASE WHEN session.lastSeen IS NULL OR excluded.lastSeen > session.lastSeen THEN COALESCE(excluded.lastSeen, session.lastSeen) ELSE session.lastSeen END,
                      delegated = MAX(session.delegated, excluded.delegated)
                    """, arguments: [s.agent.rawValue, s.sessionId, s.cwd, s.firstSeen?.timeIntervalSince1970, s.lastSeen?.timeIntervalSince1970, s.delegated])
            }
            for h in batch.codexHeaders {
                try db.execute(sql: """
                    INSERT INTO codexSession (sessionId, cwd, delegated, startedAt) VALUES (?, ?, ?, ?)
                    ON CONFLICT(sessionId) DO UPDATE SET cwd = COALESCE(excluded.cwd, codexSession.cwd), delegated = excluded.delegated,
                      startedAt = COALESCE(excluded.startedAt, codexSession.startedAt)
                    """, arguments: [h.sessionId, h.cwd, h.isDelegated, h.startedAt?.timeIntervalSince1970])
            }
            if let (path, c) = batch.cursor {
                try db.execute(sql: """
                    INSERT INTO fileCursor (path, inode, size, offset, headLength, headHash) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET inode = excluded.inode, size = excluded.size, offset = excluded.offset,
                      headLength = excluded.headLength, headHash = excluded.headHash
                    """, arguments: [path, Int64(bitPattern: c.inode), c.size, c.offset, c.headLength, c.headHash])
            }
        }
    }

    public func cursor(for path: String) throws -> FileCursor? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM fileCursor WHERE path = ?", arguments: [path]).map { row in
                FileCursor(inode: UInt64(bitPattern: row["inode"] as Int64), size: row["size"], offset: row["offset"],
                           headLength: row["headLength"], headHash: row["headHash"])
            }
        }
    }

    public func reassignOwners(mapper: ProjectMapper) throws {
        try dbQueue.write { db in
            func owner(_ cwd: String) -> (String?, String?) {
                switch mapper.map(cwd) {
                case .project(let id): return (id, nil)
                case .other(let label): return (nil, label)
                }
            }
            for cwd in try String.fetchAll(db, sql: "SELECT DISTINCT cwd FROM ownerMessage WHERE cwd IS NOT NULL") {
                let (id, label) = owner(cwd)
                try db.execute(sql: "UPDATE ownerMessage SET projectId = ?, otherLabel = ? WHERE cwd = ?", arguments: [id, label, cwd])
            }
            for cwd in try String.fetchAll(db, sql: "SELECT DISTINCT cwd FROM session WHERE cwd IS NOT NULL") {
                let (id, label) = owner(cwd)
                try db.execute(sql: "UPDATE session SET projectId = ?, otherLabel = ? WHERE cwd = ?", arguments: [id, label, cwd])
            }
            for row in try Row.fetchAll(db, sql: "SELECT sessionId, cwd FROM codexSession WHERE cwd IS NOT NULL") {
                let (id, label) = owner(row["cwd"])
                try db.execute(sql: "UPDATE ownerMessage SET projectId = ?, otherLabel = ? WHERE agent = 'codex' AND cwd IS NULL AND sessionId = ?",
                               arguments: [id, label, row["sessionId"] as String])
                try db.execute(sql: "UPDATE session SET projectId = ?, otherLabel = ? WHERE agent = 'codex' AND cwd IS NULL AND sessionId = ?",
                               arguments: [id, label, row["sessionId"] as String])
            }
        }
    }

    /// Owner messages after source precedence (history wins per session) and without delegated Codex sessions.
    public func effectiveMessages() throws -> [(message: OwnerMessage, projectId: String?, otherLabel: String?)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: Self.effectiveMessagesSQL).compactMap { row in
                guard let agent = Agent(rawValue: row["agent"]), let source = MessageSource(rawValue: row["source"]) else { return nil }
                let message = OwnerMessage(agent: agent, sessionId: row["sessionId"], timestamp: Date(timeIntervalSince1970: row["ts"]),
                                           cwd: row["cwd"], source: source)
                return (message, row["projectId"], row["otherLabel"])
            }
        }
    }

    public func projectRows(today: String, gap: TimeInterval) throws -> [ProjectRow] {
        let messages = try effectiveMessages()
        var byProject: [String: [OwnerMessage]] = [:]
        for entry in messages {
            if let id = entry.projectId { byProject[id, default: []].append(entry.message) }
        }
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            let sessionLast = Dictionary(try Row.fetchAll(db, sql: """
                SELECT projectId, agent, MAX(lastSeen) AS last FROM session s
                WHERE projectId IS NOT NULL AND delegated = 0
                  AND NOT EXISTS (SELECT 1 FROM codexSession c WHERE s.agent = 'codex' AND c.sessionId = s.sessionId AND c.delegated = 1)
                GROUP BY projectId, agent
                """).map { row -> (String, (Agent, Date))? in
                guard let last = row["last"] as Double?, let agent = Agent(rawValue: row["agent"]) else { return nil }
                return (row["projectId"], (agent, Date(timeIntervalSince1970: last)))
            }.compactMap { $0 }, uniquingKeysWith: { $0.1 > $1.1 ? $0 : $1 })

            return try Row.fetchAll(db, sql: """
                SELECT p.*, s.status, s.lastCommitAt, s.readme, s.spec, s.activeTasksOpen, s.error, s.architecture, v.visibility,
                  (SELECT MAX(lastFetchAt) FROM snapshot f WHERE f.projectId = p.id) AS lastFetchAt
                FROM project p
                LEFT JOIN snapshot s ON s.projectId = p.id AND s.day = (SELECT MAX(day) FROM snapshot x WHERE x.projectId = p.id AND x.day <= ?)
                LEFT JOIN repoVisibility v ON v.projectId = p.id
                ORDER BY p.displayName COLLATE NOCASE
                """, arguments: [today]).map { row in
                let id: String = row["id"]
                let own = byProject[id] ?? []
                let total = unionIntervals(ownerIntervals(own, gap: gap)).reduce(0) { $0 + $1.duration }
                var lastAt = own.map(\.timestamp).max()
                var lastAgent = own.max { $0.timestamp < $1.timestamp }?.agent
                if let (agent, date) = sessionLast[id], lastAt == nil || date > lastAt! {
                    lastAt = date
                    lastAgent = agent
                }
                func decode<T: Decodable>(_ type: T.Type, _ column: String) -> T? {
                    (row[column] as String?).flatMap { try? decoder.decode(T.self, from: Data($0.utf8)) }
                }
                return ProjectRow(
                    id: id, displayName: row["displayName"], summary: row["summary"], path: row["path"],
                    state: ProjectState(rawValue: row["state"]) ?? .active, pinned: row["pinned"],
                    lastActivityAt: lastAt, lastActivityAgent: lastAgent,
                    lastCommitAt: (row["lastCommitAt"] as Double?).map { Date(timeIntervalSince1970: $0) },
                    status: decode(GitStatus.self, "status"),
                    lastFetchAt: (row["lastFetchAt"] as Double?).map { Date(timeIntervalSince1970: $0) },
                    readme: decode(ReadmeDrift.self, "readme"), spec: decode(SpecHeadline.self, "spec"),
                    activeTasksOpen: row["activeTasksOpen"], error: row["error"], totalSeconds: total,
                    architecture: decode(ArchitectureDoc.self, "architecture"),
                    visibility: (row["visibility"] as String?).flatMap(RepoVisibility.init(rawValue:)),
                    isTableProject: (row["projectTablePath"] as String?) != nil
                )
            }
        }
    }

    public func visibilityChecks() throws -> [String: VisibilityCheck] {
        try dbQueue.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT projectId, visibility, checkedAt FROM repoVisibility").compactMap { row in
                (RepoVisibility(rawValue: row["visibility"])).map { (row["projectId"] as String, VisibilityCheck(visibility: $0, checkedAt: Date(timeIntervalSince1970: row["checkedAt"]))) }
            })
        }
    }

    /// nil removes the stored answer (the remote is gone or no longer recognised).
    public func writeVisibility(projectId: String, _ check: VisibilityCheck?) throws {
        try dbQueue.write { db in
            if let check {
                try db.execute(sql: """
                    INSERT INTO repoVisibility (projectId, visibility, checkedAt) VALUES (?, ?, ?)
                    ON CONFLICT(projectId) DO UPDATE SET visibility = excluded.visibility, checkedAt = excluded.checkedAt
                    """, arguments: [projectId, check.visibility.rawValue, check.checkedAt.timeIntervalSince1970])
            } else {
                try db.execute(sql: "DELETE FROM repoVisibility WHERE projectId = ?", arguments: [projectId])
            }
        }
    }

    // MARK: Test support

    func messageCount() throws -> Int { try dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ownerMessage") ?? 0 } }
    func commitDayCount(projectId: String) throws -> Int {
        try dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM commitDay WHERE projectId = ?", arguments: [projectId]) ?? 0 }
    }
    func snapshotCount() throws -> Int { try dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM snapshot") ?? 0 } }
    func sessionCount(projectId: String) throws -> Int {
        try dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM session WHERE projectId = ?", arguments: [projectId]) ?? 0 }
    }
    func checkpoint() throws {
        try dbQueue.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
    }

    static let effectiveMessagesSQL = """
        SELECT m.* FROM ownerMessage m
        WHERE NOT (m.source = 'transcript' AND EXISTS (
            SELECT 1 FROM ownerMessage h WHERE h.agent = m.agent AND h.sessionId = m.sessionId AND h.source = 'history'))
          AND NOT EXISTS (SELECT 1 FROM codexSession c WHERE m.agent = 'codex' AND c.sessionId = m.sessionId AND c.delegated = 1)
          AND NOT EXISTS (SELECT 1 FROM session s WHERE s.agent = m.agent AND s.sessionId = m.sessionId AND s.delegated = 1)
        """
}

private func json<T: Encodable>(_ value: T?) throws -> String? {
    guard let value else { return nil }
    return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}
