import Foundation

public struct SourceProblem: Sendable, Equatable {
    public enum Kind: Sendable { case root, vault, claudeHistory, claudeTranscripts, codexHistory, codexSessions }
    public enum Reason: Sendable { case missing, unreadable }

    public let kind: Kind
    public let path: String
    public let reason: Reason

    public var message: String {
        if kind == .root, path.isEmpty { return "No folder selected to scan." }
        let name = switch kind {
        case .root: "Folder"
        case .vault: "Vault"
        case .claudeHistory: "Claude history"
        case .claudeTranscripts: "Claude sessions"
        case .codexHistory: "Codex history"
        case .codexSessions: "Codex sessions"
        }
        return "\(name) \(reason == .missing ? "not found" : "cannot be read"): \(path)"
    }
}

/// Sources the scan reads; a missing or unreadable one is named so the UI never shows empty data in its place.
public func checkSources(_ config: ScanConfig, vaultConfigured: Bool, fileManager: FileManager = .default) -> [SourceProblem] {
    var problems: [SourceProblem] = []
    func check(_ kind: SourceProblem.Kind, _ url: URL, directory: Bool) {
        let path = url.path
        guard fileManager.fileExists(atPath: path) else {
            problems.append(SourceProblem(kind: kind, path: path, reason: .missing))
            return
        }
        let readable = directory ? (try? fileManager.contentsOfDirectory(atPath: path)) != nil : fileManager.isReadableFile(atPath: path)
        if !readable { problems.append(SourceProblem(kind: kind, path: path, reason: .unreadable)) }
    }
    if config.roots.isEmpty { problems.append(SourceProblem(kind: .root, path: "", reason: .missing)) }
    for root in config.roots { check(.root, root, directory: true) }
    if vaultConfigured { check(.vault, config.vaultRoot, directory: true) }
    // Agent sources are optional: a missing one means the tool is not used, only an unreadable one is a problem.
    for (kind, url, directory) in [(SourceProblem.Kind.claudeHistory, config.claudeHome.appendingPathComponent("history.jsonl"), false),
                                   (.claudeTranscripts, config.claudeHome.appendingPathComponent("projects"), true),
                                   (.codexHistory, config.codexHome.appendingPathComponent("history.jsonl"), false),
                                   (.codexSessions, config.codexHome.appendingPathComponent("sessions"), true)]
    where fileManager.fileExists(atPath: url.path) {
        check(kind, url, directory: directory)
    }
    return problems
}
