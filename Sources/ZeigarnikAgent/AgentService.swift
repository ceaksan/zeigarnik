import Foundation
import ZeigarnikCore

/// Version reported by `zeigarnik --version` and the MCP server; kept in step with `MARKETING_VERSION` in project.yml.
public let zeigarnikVersion = "0.2.2"

public enum AgentError: Error, Equatable, CustomStringConvertible {
    case unknownProject(String)
    case ambiguousProject(String, [String])
    case unknownNote(String)
    case ambiguousNote(String)
    case noteIdTooShort(String)
    case emptyText
    case invalidDay(String)
    case missingArgument(String)

    public var description: String {
        switch self {
        case .unknownProject(let ref): "No project named \"\(ref)\". Use an id, a name or a path from list_projects."
        case .ambiguousProject(let ref, let paths): "\"\(ref)\" names several projects; use a path: \(paths.joined(separator: ", "))"
        case .unknownNote(let ref): "No note with id \"\(ref)\"."
        case .ambiguousNote(let ref): "\"\(ref)\" matches several notes; give more of the id."
        case .noteIdTooShort(let ref): "Note id \"\(ref)\" is too short; give at least 4 characters."
        case .emptyText: "Note text is empty."
        case .invalidDay(let day): "\"\(day)\" is not a day; use YYYY-MM-DD."
        case .missingArgument(let name): "Missing argument: \(name)."
        }
    }
}

public struct NoteRecord: Sendable, Equatable, Codable {
    public let id: String
    public let projectId: String
    public let project: String
    public let day: String
    public let text: String
    public let createdAt: Date
}

public struct DraftRecord: Sendable, Equatable, Codable {
    public let projectId: String
    public let project: String
    public let kind: NoteDraftKind
    public let text: String
}

public struct ProjectSummary: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let path: String
    public let state: ProjectState
    public let pinned: Bool
    public let lastActivityAt: Date?
    public let lastCommitAt: Date?
    public let branch: String?
    public let push: String
    public let uncommittedFiles: Int?
    public let readme: String
    public let architecture: String
    public let activeTasksOpen: Int?
    public let notes: Int
    public let openDrafts: Int
}

public struct ProjectStatus: Sendable, Equatable, Codable {
    public let project: ProjectSummary
    public let summary: String?
    public let notes: [NoteRecord]
    public let drafts: [DraftRecord]
}

/// Notes, projects and drafts for the command-line tool and the MCP server. Notes are never deleted through MCP;
/// `deleteNote` exists for the command line only (ADR-006).
public final class AgentService: Sendable {
    let store: Store
    let now: @Sendable () -> Date
    let calendar: Calendar
    let gap: TimeInterval
    let checks: NoteDraftChecks

    public init(store: Store, now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current,
                gap: TimeInterval = 900, checks: NoteDraftChecks = .all) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.gap = gap
        self.checks = checks
    }

    var today: String { dayKey(now(), calendar: calendar) }

    // MARK: Projects

    /// An id, a path (`~` allowed, trailing slash ignored) or a display name in any letter case.
    public func resolveProject(_ ref: String) throws -> String {
        let refs = try store.projectRefs()
        if let match = refs.first(where: { $0.id == ref }) { return match.id }
        let path = ((ref as NSString).expandingTildeInPath as NSString).standardizingPath
        if let match = refs.first(where: { $0.path == path }) { return match.id }
        let named = refs.filter { $0.displayName.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count > 1 { throw AgentError.ambiguousProject(ref, named.map(\.path).sorted()) }
        guard let match = named.first else { throw AgentError.unknownProject(ref) }
        return match.id
    }

    public func projects(matching query: String? = nil) throws -> [ProjectSummary] {
        let rows = try store.projectRows(today: today, gap: gap)
        let counts = try store.noteCounts()
        let drafts = try openDrafts(rows)
        let query = query?.trimmingCharacters(in: .whitespaces) ?? ""
        return rows.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }
            .map { row in summary(row, notes: counts[row.id] ?? 0, drafts: drafts.filter { $0.projectId == row.id }.count) }
    }

    public func projectStatus(_ ref: String, recentNotes: Int = 20) throws -> ProjectStatus {
        let id = try resolveProject(ref)
        guard let row = try store.projectRows(today: today, gap: gap).first(where: { $0.id == id }) else { throw AgentError.unknownProject(ref) }
        let drafts = try openDrafts([row])
        let notes = try store.notes(projectId: id, fromDay: nil, toDay: nil, limit: recentNotes)
        let count = try store.noteCounts()[id] ?? 0
        return ProjectStatus(project: summary(row, notes: count, drafts: drafts.count), summary: row.summary,
                             notes: notes.map { record($0, name: row.displayName) }, drafts: drafts.map { draft($0, name: row.displayName) })
    }

    // MARK: Notes

    public func notes(project: String?, since: String?, until: String?, limit: Int?) throws -> [NoteRecord] {
        let projectId = try project.map(resolveProject)
        if let since { try requireDay(since) }
        if let until { try requireDay(until) }
        let names = try nameLookup()
        return try store.notes(projectId: projectId, fromDay: since, toDay: until, limit: limit).map { record($0, name: names[$0.projectId]) }
    }

    public func note(_ ref: String) throws -> NoteRecord {
        let note = try findNote(ref)
        return record(note, name: try store.displayName(projectId: note.projectId))
    }

    public func addNote(project: String, text: String, day: String?) throws -> NoteRecord {
        let projectId = try resolveProject(project)
        if let day { try requireDay(day) }
        let note = try mapped { try store.addNote(projectId: projectId, day: day ?? today, text: text, now: now()) }
        return record(note, name: try store.displayName(projectId: projectId))
    }

    public func updateNote(_ ref: String, text: String) throws -> NoteRecord {
        let existing = try findNote(ref)
        let note = try mapped { try store.updateNote(id: existing.id, text: text) }
        return record(note, name: try store.displayName(projectId: note.projectId))
    }

    /// Command line only; the MCP server has no delete tool.
    public func deleteNote(_ ref: String) throws -> NoteRecord {
        let note = try findNote(ref)
        try store.deleteNote(id: note.id)
        return record(note, name: try store.displayName(projectId: note.projectId))
    }

    // MARK: Drafts

    public func drafts(project: String?) throws -> [DraftRecord] {
        var rows = try store.projectRows(today: today, gap: gap)
        if let project {
            let id = try resolveProject(project)
            rows = rows.filter { $0.id == id }
        }
        let names = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.displayName) })
        return try openDrafts(rows).map { draft($0, name: names[$0.projectId]) }
    }

    // MARK: Helpers

    private func openDrafts(_ rows: [ProjectRow]) throws -> [NoteDraft] {
        try store.openNoteDrafts(rows.flatMap { noteDrafts(for: $0, checks: checks) }, projectIds: Set(rows.map(\.id)))
    }

    private func findNote(_ ref: String) throws -> Note {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { throw AgentError.noteIdTooShort(trimmed) }
        let matches = try store.notes(idPrefix: trimmed, limit: 2)
        guard !matches.isEmpty else { throw AgentError.unknownNote(trimmed) }
        guard matches.count == 1 else { throw AgentError.ambiguousNote(trimmed) }
        return matches[0]
    }

    private func requireDay(_ day: String) throws {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)),
              dayKey(date, calendar: calendar) == day
        else { throw AgentError.invalidDay(day) }
    }

    private func mapped<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch OwnerDataError.emptyText { throw AgentError.emptyText }
    }

    private func nameLookup() throws -> [String: String] {
        Dictionary(try store.projectRefs().map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    private func record(_ note: Note, name: String?) -> NoteRecord {
        NoteRecord(id: note.id.uuidString, projectId: note.projectId, project: name ?? note.projectId, day: note.day, text: note.text,
                   createdAt: note.createdAt)
    }

    private func draft(_ draft: NoteDraft, name: String?) -> DraftRecord {
        DraftRecord(projectId: draft.projectId, project: name ?? draft.projectId, kind: draft.kind, text: draft.text)
    }

    private func summary(_ row: ProjectRow, notes: Int, drafts: Int) -> ProjectSummary {
        ProjectSummary(id: row.id, name: row.displayName, path: row.path, state: row.state, pinned: row.pinned,
                       lastActivityAt: row.lastActivityAt, lastCommitAt: row.lastCommitAt, branch: row.status?.branch,
                       push: Self.push(row.status), uncommittedFiles: row.status.map { $0.changed + $0.untracked },
                       readme: Self.readme(row.readme), architecture: Self.architecture(row.architecture),
                       activeTasksOpen: row.activeTasksOpen, notes: notes, openDrafts: drafts)
    }

    static func push(_ status: GitStatus?) -> String {
        guard let status else { return "unknown" }
        guard status.branch != nil else { return "detached" }
        guard status.upstream != nil else { return "no upstream" }
        let parts = [(status.ahead ?? 0) > 0 ? "\(status.ahead!) to push" : nil, (status.behind ?? 0) > 0 ? "\(status.behind!) to pull" : nil]
            .compactMap { $0 }
        return parts.isEmpty ? "in sync" : parts.joined(separator: ", ")
    }

    static func readme(_ drift: ReadmeDrift?) -> String {
        switch drift {
        case nil: "unknown"
        case .noReadme?: "none"
        case .current?: "up to date"
        case .behind(let commits, _, let manifest)?: "\(commits) commits behind" + (manifest ? ", manifest changed" : "")
        }
    }

    static func architecture(_ doc: ArchitectureDoc?) -> String {
        switch doc {
        case nil: "unknown"
        case .none?: "none"
        case .current?: "up to date"
        case .behind(_, _, let since, _, _, _)?: "behind (\(since) commits since its last update)"
        }
    }
}
