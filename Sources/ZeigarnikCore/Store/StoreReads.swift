import Foundation
import GRDB

extension Store {
    public func specSummaries(projectId: String) throws -> [SpecSummary] {
        let decoder = JSONDecoder()
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT json FROM specEvidence WHERE projectId = ? ORDER BY specPath", arguments: [projectId])
                .compactMap { try? decoder.decode(SpecSummary.self, from: Data($0.utf8)) }
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
