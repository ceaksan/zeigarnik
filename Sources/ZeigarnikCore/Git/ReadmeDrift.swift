import Foundation

public enum ReadmeDrift: Sendable, Equatable, Codable {
    case noReadme
    case current
    case behind(commits: Int, codeFiles: Int, manifestChanged: Bool)
}

public let manifestFileNames: Set<String> = ["package.json", "pyproject.toml", "requirements.txt", "Cargo.toml", "Package.swift", "project.yml", ".env.example"]

public func findReadme(in files: Set<String>) -> String? {
    let candidates = files.filter { !$0.contains("/") && ["readme.md", "readme"].contains($0.lowercased()) }
    return candidates.sorted().first
}

public func readmeDrift(history: [CommitRecord], readmePath: String?, minCommits: Int = 3) -> ReadmeDrift {
    guard let readmePath else { return .noReadme }
    let since = history.prefix { !$0.files.contains(readmePath) }
    var codeFiles = Set<String>()
    var manifestChanged = false
    for commit in since {
        for file in commit.files {
            if manifestFileNames.contains((file as NSString).lastPathComponent) { manifestChanged = true }
            if !file.hasPrefix("docs/") && !file.lowercased().hasSuffix(".md") { codeFiles.insert(file) }
        }
    }
    if manifestChanged || (!codeFiles.isEmpty && since.count >= minCommits) {
        return .behind(commits: since.count, codeFiles: codeFiles.count, manifestChanged: manifestChanged)
    }
    return .current
}

public func readmeSummary(_ markdown: String, maxLength: Int = 160) -> String? {
    var lines = markdown.components(separatedBy: "\n")[...]
    if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
        lines = lines.dropFirst()
        if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines = lines[lines.index(after: end)...]
        }
    }
    var paragraph: [String] = []
    var inFence = false
    for raw in lines {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            if !paragraph.isEmpty { break }
            inFence.toggle()
            continue
        }
        if inFence { continue }
        let isNoise = line.hasPrefix("#") || line.hasPrefix("![") || line.hasPrefix("[![") || line.hasPrefix("<")
            || line.hasPrefix(">") || line.hasPrefix("|") || line.hasPrefix("---")
        if line.isEmpty || isNoise {
            if !paragraph.isEmpty { break }
            continue
        }
        paragraph.append(line)
    }
    guard !paragraph.isEmpty else { return nil }
    var text = paragraph.joined(separator: " ")
    text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
    text = text.replacingOccurrences(of: "**", with: "")
    guard text.count > maxLength else { return text }
    let cut = text.prefix(maxLength)
    let trimmed = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
    return trimmed.trimmingCharacters(in: .whitespaces) + "…"
}
