import Foundation

public struct GitStatus: Sendable, Equatable, Codable {
    public var branch: String?
    public var upstream: String?
    public var ahead: Int?
    public var behind: Int?
    public var changed: Int
    public var untracked: Int
    public var stash: Int

    public init(branch: String?, upstream: String?, ahead: Int?, behind: Int?, changed: Int, untracked: Int, stash: Int) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changed = changed
        self.untracked = untracked
        self.stash = stash
    }
}

/// Parses `git status --porcelain=v2 -z --branch --show-stash` output.
public func parsePorcelainV2(_ data: Data) -> GitStatus {
    var status = GitStatus(branch: nil, upstream: nil, ahead: nil, behind: nil, changed: 0, untracked: 0, stash: 0)
    let fields = data.split(separator: 0, omittingEmptySubsequences: true)
    var skipNext = false
    for field in fields {
        if skipNext {
            skipNext = false
            continue
        }
        guard let first = field.first else { continue }
        switch first {
        case UInt8(ascii: "#"):
            let line = String(decoding: field, as: UTF8.self)
            if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                status.branch = head == "(detached)" ? nil : head
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 {
                    status.ahead = Int(parts[0].dropFirst())
                    status.behind = Int(parts[1].dropFirst())
                }
            } else if line.hasPrefix("# stash ") {
                status.stash = Int(line.dropFirst("# stash ".count)) ?? 0
            }
        case UInt8(ascii: "1"), UInt8(ascii: "u"):
            status.changed += 1
        case UInt8(ascii: "2"):
            status.changed += 1
            skipNext = true
        case UInt8(ascii: "?"):
            status.untracked += 1
        default:
            break
        }
    }
    return status
}

public func parseWorktreeList(_ output: String) -> [URL] {
    output.split(separator: "\n").compactMap { line in
        guard line.hasPrefix("worktree ") else { return nil }
        return URL(fileURLWithPath: String(line.dropFirst("worktree ".count))).standardizedFileURL
    }
}

public func aggregateStatus(main: GitStatus, others: [GitStatus]) -> GitStatus {
    var result = main
    for other in others {
        result.changed += other.changed
        result.untracked += other.untracked
    }
    return result
}
