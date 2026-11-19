import Foundation

public enum DeclaredKind: Sendable, Equatable {
    case approval, completion, other, none
}

private let approvalWords: Set<String> = ["draft", "proposed", "approved", "accepted"]
private let completionWords: Set<String> = ["done", "implemented", "complete", "completed", "shipped", "released"]

/// Status from YAML frontmatter, or from a `Status:` line before the first `## ` heading, never inside fenced code.
public func declaredStatus(_ markdown: String) -> String? {
    var lines = markdown.components(separatedBy: "\n")[...]
    if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
        lines = lines.dropFirst()
        while let line = lines.first, line.trimmingCharacters(in: .whitespaces) != "---" {
            if let match = line.firstMatch(of: /^\s*status:\s*(.+)$/.ignoresCase()) {
                return String(match.1).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            lines = lines.dropFirst()
        }
        lines = lines.dropFirst()
    }
    var inFence = false
    for raw in lines {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            inFence.toggle()
            continue
        }
        if inFence { continue }
        if line.hasPrefix("## ") { return nil }
        if let match = line.firstMatch(of: /^(?:\*\*Status:\*\*|Status:)\s*(.+)$/) {
            return String(match.1).trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

public func classifyStatus(_ value: String?) -> DeclaredKind {
    guard let value else { return .none }
    let first = value.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).first.map { $0.lowercased() } ?? ""
    let word = first.trimmingCharacters(in: .punctuationCharacters)
    if approvalWords.contains(word) { return .approval }
    if completionWords.contains(word) { return .completion }
    return .other
}
