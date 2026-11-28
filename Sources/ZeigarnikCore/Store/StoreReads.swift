import Foundation
import GRDB

extension Store {
    public func specSummaries(projectId: String) throws -> [SpecSummary] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT e.json, o.state FROM specEvidence e
                LEFT JOIN specOverride o ON o.projectId = e.projectId AND o.specPath = e.specPath
                WHERE e.projectId = ? ORDER BY e.specPath
                """, arguments: [projectId]).map { row in
                    let json: String = row["json"]
                    let override = (row["state"] as String?).flatMap(OwnerSpecOverride.init(rawValue:))
                    return try decoder.decode(SpecSummary.self, from: Data(json.utf8)).applyingOverride(override)
                }
        }
    }

    public func commitDays() throws -> [(projectId: String, day: String, count: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT projectId, day, count FROM commitDay ORDER BY day, projectId")
                .map { (projectId: $0["projectId"], day: $0["day"], count: $0["count"]) }
        }
    }

    /// Active projects at their current path only; past paths and missing projects are left out.
    public func currentProjectPaths() throws -> [(id: String, path: String)] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, path FROM project WHERE state = 'active' ORDER BY path")
                .map { (id: $0["id"], path: $0["path"]) }
        }
    }

    public func displayName(projectId: String) throws -> String? {
        try dbQueue.read { db in try String.fetchOne(db, sql: "SELECT displayName FROM project WHERE id = ?", arguments: [projectId]) }
    }
}

public struct ProjectRef: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let path: String
    public let state: ProjectState
}

extension Store {
    /// Every project with its current path; enough to resolve a name without reading activity.
    public func projectRefs() throws -> [ProjectRef] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, displayName, path, state FROM project ORDER BY displayName COLLATE NOCASE, path").map {
                ProjectRef(id: $0["id"], displayName: $0["displayName"], path: $0["path"], state: ProjectState(rawValue: $0["state"]) ?? .active)
            }
        }
    }

    /// Newest first: by day, then by creation time. Each filter is optional; days are inclusive.
    public func notes(projectId: String?, fromDay: String?, toDay: String?, limit: Int?) throws -> [Note] {
        var clauses: [String] = []
        var arguments: StatementArguments = []
        if let projectId { clauses.append("projectId = ?"); arguments += [projectId] }
        if let fromDay { clauses.append("day >= ?"); arguments += [fromDay] }
        if let toDay { clauses.append("day <= ?"); arguments += [toDay] }
        let filter = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let cap = limit.map { " LIMIT \(max(0, $0))" } ?? ""
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM note \(filter) ORDER BY day DESC, createdAt DESC\(cap)", arguments: arguments)
                .compactMap(Self.note)
        }
    }

    /// Notes whose id starts with `prefix` (case-insensitive), at most `limit`. A prefix with other characters than
    /// hexadecimal digits and dashes matches nothing.
    public func notes(idPrefix: String, limit: Int) throws -> [Note] {
        let prefix = idPrefix.uppercased()
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return [] }
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM note WHERE id LIKE ? ORDER BY id LIMIT ?", arguments: [prefix + "%", limit])
                .compactMap(Self.note)
        }
    }

    public func noteCounts() throws -> [String: Int] {
        try dbQueue.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT projectId, COUNT(*) AS n FROM note GROUP BY projectId")
                .map { ($0["projectId"] as String, $0["n"] as Int) })
        }
    }

    /// Changes only when another connection commits (`PRAGMA data_version`); this store's own writes leave it as it is.
    public func dataVersion() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "PRAGMA data_version") ?? 0 }
    }
}
