import Foundation

public struct DiscoveryResult: Sendable, Equatable {
    public var repos: [URL]
    public var enumeratedRoots: Set<URL>
    /// Enumerated roots where some subdirectory could not be listed; nothing under them may be marked missing.
    public var incompleteRoots: Set<URL>
    public var errors: [String]

    public init(repos: [URL] = [], enumeratedRoots: Set<URL> = [], incompleteRoots: Set<URL> = [], errors: [String] = []) {
        self.repos = repos
        self.enumeratedRoots = enumeratedRoots
        self.incompleteRoots = incompleteRoots
        self.errors = errors
    }
}

private let skippedDirectoryNames: Set<String> = ["node_modules", ".build", ".venv", "build", "dist"]

public func discoverRepositories(roots: [URL], maxDepth: Int = 4) -> DiscoveryResult {
    var result = DiscoveryResult()
    let fm = FileManager.default
    for root in roots {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue,
              (try? fm.contentsOfDirectory(atPath: root.path)) != nil else {
            result.errors.append("Cannot read root \(root.path)")
            continue
        }
        result.enumeratedRoots.insert(root)
        let errorsBefore = result.errors.count
        walk(root, depth: 0, maxDepth: maxDepth, into: &result)
        if result.errors.count > errorsBefore { result.incompleteRoots.insert(root) }
    }
    result.repos.sort { $0.path < $1.path }
    return result
}

private func walk(_ dir: URL, depth: Int, maxDepth: Int, into result: inout DiscoveryResult) {
    let fm = FileManager.default
    if depth > 0, fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
        result.repos.append(dir.standardizedFileURL)
        return
    }
    guard depth < maxDepth else { return }
    let children: [URL]
    do {
        children = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
    } catch {
        result.errors.append("Cannot list \(dir.path): \(error.localizedDescription)")
        return
    }
    for child in children {
        let name = child.lastPathComponent
        if name.hasPrefix(".") || skippedDirectoryNames.contains(name) { continue }
        let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
        walk(child, depth: depth + 1, maxDepth: maxDepth, into: &result)
    }
}
