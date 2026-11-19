import Foundation

public enum ActivityOwner: Sendable, Hashable, Codable {
    case project(String)
    case other(String)
}

public struct ProjectMapper: Sendable {
    private let projects: [(id: String, path: String)]
    private let home: String
    private let workspaceRoot: String

    public init(projects: [(id: String, path: String)], home: String, workspaceRoot: String) {
        self.projects = projects.map { (id: $0.id, path: normalizedActivityPath($0.path)) }
            .sorted { $0.path.count > $1.path.count }
        self.home = normalizedActivityPath(home)
        self.workspaceRoot = normalizedActivityPath(workspaceRoot)
    }

    public func map(_ cwd: String) -> ActivityOwner {
        let path = normalizedActivityPath(cwd)
        if let project = projects.first(where: { activityPath(path, isWithin: $0.path) }) {
            return .project(project.id)
        }
        if path == workspaceRoot { return .other((workspaceRoot as NSString).lastPathComponent) }
        if path == home { return .other("~") }
        if activityPath(path, isWithin: home) {
            let relative = String(path.dropFirst(home.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return .other("~/" + relative)
        }
        return .other(path)
    }
}

private func normalizedActivityPath(_ path: String) -> String {
    URL(fileURLWithPath: path.precomposedStringWithCanonicalMapping)
        .standardizedFileURL.path.precomposedStringWithCanonicalMapping
}

private func activityPath(_ path: String, isWithin root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
}
