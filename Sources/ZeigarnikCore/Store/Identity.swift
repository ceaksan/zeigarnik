import Foundation

public enum ProjectState: String, Sendable, Codable {
    case active, missing
}

public struct KnownProject: Sendable, Equatable {
    public let id: String
    public let path: String
    public let state: ProjectState
    public let identity: GitIdentity?

    public init(id: String, path: String, state: ProjectState, identity: GitIdentity?) {
        self.id = id
        self.path = path
        self.state = state
        self.identity = identity
    }
}

public enum IdentityResolution: Sendable, Equatable {
    case existing(String)
    case relinked(String, fromPath: String)
    case new
    case ambiguous([String])
}

public func resolveIdentity(path: String, identity: GitIdentity?, known: [KnownProject], pathExists: (String) -> Bool) -> IdentityResolution {
    if let same = known.first(where: { $0.path == path }) { return .existing(same.id) }
    guard let identity, !identity.rootCommits.isEmpty else { return .new }
    let candidates = known.filter { project in
        guard !pathExists(project.path), let other = project.identity,
              !other.rootCommits.isDisjoint(with: identity.rootCommits) else { return false }
        if let a = other.remoteURL, let b = identity.remoteURL, a != b { return false }
        return true
    }
    switch candidates.count {
    case 0: return .new
    case 1: return .relinked(candidates[0].id, fromPath: candidates[0].path)
    default: return .ambiguous(candidates.map(\.id).sorted())
    }
}
