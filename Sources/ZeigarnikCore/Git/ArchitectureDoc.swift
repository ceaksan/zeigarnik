import Foundation

/// State of a project's architecture document against the code that changed since it was last committed.
public enum ArchitectureDoc: Sendable, Equatable, Codable {
    case none
    case current(path: String, updatedAt: Date?, commitsSince: Int)
    case behind(path: String, updatedAt: Date?, commitsSince: Int, newDirectories: [String], newFiles: Int, manifestChanged: Bool)
}

/// `ARCHITECTURE.md` / `architecture.md` at the root, otherwise `docs/architecture.md`, in any letter case.
public func findArchitectureDoc(in files: Set<String>) -> String? {
    let root = files.filter { !$0.contains("/") && $0.lowercased() == "architecture.md" }.sorted()
    if let first = root.first { return first }
    return files.filter { $0.lowercased() == "docs/architecture.md" }.sorted().first
}

/// Behind when, since the document's last commit, a new module folder appeared, `newFileThreshold` or more new code
/// files were added, or a manifest changed. New means first seen after that commit; deletions are not detected.
public func architectureDoc(history: [CommitRecord], path: String?, newFileThreshold: Int = 5) -> ArchitectureDoc {
    guard let path else { return .none }
    guard let docIndex = history.firstIndex(where: { $0.files.contains(path) }) else {
        return .current(path: path, updatedAt: nil, commitsSince: 0)
    }
    let since = history[..<docIndex]
    let knownFiles = Set(history[docIndex...].flatMap(\.files))
    let knownDirectories = Set(knownFiles.compactMap(moduleDirectory))
    var newFiles = Set<String>()
    var manifestChanged = false
    for commit in since {
        for file in commit.files {
            if manifestFileNames.contains((file as NSString).lastPathComponent) { manifestChanged = true }
            if !knownFiles.contains(file) && isArchitectureRelevant(file) { newFiles.insert(file) }
        }
    }
    let newDirectories = Set(newFiles.compactMap(moduleDirectory)).subtracting(knownDirectories).sorted()
    let updatedAt = history[docIndex].authorDate
    if manifestChanged || !newDirectories.isEmpty || newFiles.count >= newFileThreshold {
        return .behind(path: path, updatedAt: updatedAt, commitsSince: since.count, newDirectories: newDirectories,
                       newFiles: newFiles.count, manifestChanged: manifestChanged)
    }
    return .current(path: path, updatedAt: updatedAt, commitsSince: since.count)
}

/// The first two path components of a file's folder ("Sources/App"), or the one folder of a shallow file ("src").
private func moduleDirectory(_ file: String) -> String? {
    let parts = file.split(separator: "/")
    guard parts.count >= 2 else { return nil }
    return parts.prefix(min(2, parts.count - 1)).joined(separator: "/")
}

private func isArchitectureRelevant(_ file: String) -> Bool {
    let parts = file.split(separator: "/")
    return parts.first != "docs" && !file.lowercased().hasSuffix(".md") && !parts.contains { $0.hasPrefix(".") }
}
