import Foundation
import GRDB

public enum NoteDraftKind: String, Sendable, Codable, CaseIterable {
    case readme, architecture, push, uncommitted
}

/// A note the owner may want, derived from a project's current state. Never stored; see ADR-006.
public struct NoteDraft: Sendable, Equatable, Codable {
    public let projectId: String
    public let kind: NoteDraftKind
    public let text: String
    /// The state that produced the draft; a dismissal holds until this changes.
    public let fingerprint: String
}

public struct NoteDraftChecks: Sendable, Equatable {
    public var readme: Bool
    public var architecture: Bool

    public init(readme: Bool, architecture: Bool) {
        self.readme = readme
        self.architecture = architecture
    }

    public static let all = NoteDraftChecks(readme: true, architecture: true)
}

/// At most one draft per kind, in column order. Missing projects have none.
public func noteDrafts(for row: ProjectRow, checks: NoteDraftChecks = .all) -> [NoteDraft] {
    guard row.state == .active else { return [] }
    func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
    var drafts: [NoteDraft] = []
    func add(_ kind: NoteDraftKind, _ text: String, _ fingerprint: String) {
        drafts.append(NoteDraft(projectId: row.id, kind: kind, text: text, fingerprint: fingerprint))
    }
    if checks.readme, case .behind(let commits, _, let manifest)? = row.readme {
        add(.readme, "Update the README: \(plural(commits, "commit")) behind" + (manifest ? ", a manifest changed." : "."),
            "behind:\(commits):\(manifest)")
    }
    if checks.architecture, case .behind(let path, _, _, let dirs, let files, let manifest)? = row.architecture {
        let reasons = [dirs.isEmpty ? nil : plural(dirs.count, "new folder"), files == 0 ? nil : plural(files, "new file"),
                       manifest ? "a manifest changed" : nil].compactMap { $0 }
        add(.architecture, "Update \(path): \(reasons.joined(separator: ", ")).",
            "behind:\(dirs.joined(separator: ",")):\(files):\(manifest)")
    }
    if let status = row.status, let branch = status.branch {
        let ahead = status.ahead ?? 0
        let behind = status.behind ?? 0
        if status.upstream == nil {
            add(.push, "Branch \(branch) has no upstream; push it or set one.", "noUpstream:\(branch)")
        } else if ahead > 0 || behind > 0 {
            let parts = [ahead > 0 ? "\(plural(ahead, "commit")) to push" : nil,
                         behind > 0 ? (ahead > 0 ? "\(behind) to pull" : "\(plural(behind, "commit")) to pull") : nil].compactMap { $0 }
            add(.push, "Sync \(branch): \(parts.joined(separator: ", ")).", "\(branch):\(ahead):\(behind)")
        }
    }
    if let status = row.status, status.changed + status.untracked > 0 {
        let total = status.changed + status.untracked
        add(.uncommitted, "Commit or discard \(plural(total, "changed file")) (\(status.changed) modified, \(status.untracked) untracked).",
            "\(status.changed):\(status.untracked)")
    }
    return drafts
}

extension Store {
    public func dismissNoteDraft(_ draft: NoteDraft, now: Date) throws {
        try dbQueue.write { db in try Self.dismiss(db, draft, now: now) }
    }

    /// The drafts not dismissed at their current state. For each project in `projectIds`, a kind with no draft any more
    /// forgets its dismissal, so the same state returning later is offered again. Other projects' dismissals are untouched.
    public func openNoteDrafts(_ drafts: [NoteDraft], projectIds: Set<String>) throws -> [NoteDraft] {
        try dbQueue.write { db in
            let current = Set(drafts.map { "\($0.projectId)\u{1F}\($0.kind.rawValue)" })
            var dismissed: [String: String] = [:]
            for projectId in projectIds {
                for row in try Row.fetchAll(db, sql: "SELECT kind, fingerprint FROM noteDraftDismissal WHERE projectId = ?", arguments: [projectId]) {
                    let kind: String = row["kind"]
                    let key = "\(projectId)\u{1F}\(kind)"
                    if current.contains(key) {
                        dismissed[key] = row["fingerprint"]
                    } else {
                        try db.execute(sql: "DELETE FROM noteDraftDismissal WHERE projectId = ? AND kind = ?", arguments: [projectId, kind])
                    }
                }
            }
            return drafts.filter { dismissed["\($0.projectId)\u{1F}\($0.kind.rawValue)"] != $0.fingerprint }
        }
    }

    /// Adds the owner's text as a note and dismisses the draft in one transaction.
    public func acceptNoteDraft(_ draft: NoteDraft, text: String, day: String, now: Date) throws -> Note {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OwnerDataError.emptyText }
        let note = Note(id: UUID(), projectId: draft.projectId, day: day, text: trimmed, createdAt: now)
        try dbQueue.write { db in
            try Self.insert(db, note)
            try Self.dismiss(db, draft, now: now)
        }
        return note
    }

    private static func dismiss(_ db: Database, _ draft: NoteDraft, now: Date) throws {
        try db.execute(sql: """
            INSERT INTO noteDraftDismissal (projectId, kind, fingerprint, dismissedAt) VALUES (?, ?, ?, ?)
            ON CONFLICT(projectId, kind) DO UPDATE SET fingerprint = excluded.fingerprint, dismissedAt = excluded.dismissedAt
            """, arguments: [draft.projectId, draft.kind.rawValue, draft.fingerprint, now.timeIntervalSince1970])
    }
}
