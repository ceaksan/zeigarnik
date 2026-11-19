import Foundation

public enum RepoVisibility: String, Sendable, Codable, Equatable {
    case `public`, `private`, unknown
}

public struct RemoteRepo: Sendable, Equatable, Hashable {
    public let host: String
    public let path: String
    public init(host: String, path: String) { self.host = host; self.path = path }
}

public struct VisibilityCheck: Sendable, Equatable {
    public let visibility: RepoVisibility
    public let checkedAt: Date
    public init(visibility: RepoVisibility, checkedAt: Date) { self.visibility = visibility; self.checkedAt = checkedAt }
}

public protocol VisibilityProbing: Sendable {
    func visibility(of repo: RemoteRepo) async -> RepoVisibility
}

/// Host and `owner/name` path of a URL-style or scp-style remote; nil for local paths and `file://` remotes.
public func parseRemote(_ url: String) -> RemoteRepo? {
    var host: Substring
    var path: Substring
    if let scheme = url.range(of: "://") {
        guard !url.lowercased().hasPrefix("file:") else { return nil }
        let rest = url[scheme.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        host = rest[..<slash]
        path = rest[rest.index(after: slash)...]
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if let colon = host.firstIndex(of: ":") { host = host[..<colon] }
    } else if let colon = url.firstIndex(of: ":"), !url.hasPrefix("/") {
        host = url[..<colon]
        path = url[url.index(after: colon)...]
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
    } else {
        return nil
    }
    var cleaned = String(path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if cleaned.hasSuffix(".git") { cleaned.removeLast(4) }
    let parts = cleaned.split(separator: "/")
    guard !host.isEmpty, parts.count >= 2, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
    return RemoteRepo(host: host.lowercased(), path: cleaned)
}

public struct NetworkVisibilityProbe: VisibilityProbing {
    let runner: CommandRunning
    let ghPath: String?
    let httpStatus: @Sendable (URL) async -> Int?

    public init(runner: CommandRunning, ghPath: String?, httpStatus: @escaping @Sendable (URL) async -> Int?) {
        self.runner = runner
        self.ghPath = ghPath
        self.httpStatus = httpStatus
    }

    /// GitHub: `gh` first (it sees the owner's private repositories), then the public API.
    /// GitLab: the public API. Unauthenticated, 200 means public and 404 private; anything else is unknown.
    public func visibility(of repo: RemoteRepo) async -> RepoVisibility {
        switch repo.host {
        case "github.com":
            if let ghPath {
                let result = await runner.run(ghPath, ["repo", "view", repo.path, "--json", "visibility", "--jq", ".visibility"], cwd: nil,
                                              environment: ["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1"], timeout: .seconds(5))
                if result.exitCode == 0 {
                    switch String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                    case "PUBLIC": return .public
                    case "PRIVATE", "INTERNAL": return .private
                    default: break
                    }
                }
            }
            guard let url = URL(string: "https://api.github.com/repos/\(repo.path)") else { return .unknown }
            return Self.fromStatus(await httpStatus(url))
        case "gitlab.com":
            let encoded = repo.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? repo.path
            guard let url = URL(string: "https://gitlab.com/api/v4/projects/\(encoded)") else { return .unknown }
            return Self.fromStatus(await httpStatus(url))
        default:
            return .unknown
        }
    }

    static func fromStatus(_ status: Int?) -> RepoVisibility {
        switch status {
        case 200: .public
        case 404: .private
        default: .unknown
        }
    }
}

/// Status code of an unauthenticated GET with a 5 second timeout; nil on network failure.
public func liveHTTPStatus(_ url: URL) async -> Int? {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
    request.setValue("Zeigarnik", forHTTPHeaderField: "User-Agent")
    guard let (_, response) = try? await URLSession.shared.data(for: request) else { return nil }
    return (response as? HTTPURLResponse)?.statusCode
}
