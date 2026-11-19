import Foundation

public enum FetchOutcome: Sendable, Equatable, Codable {
    case ok(Date)
    case failed(String)
    case timedOut
    case noRemote
}

public struct GitIdentity: Sendable, Equatable, Codable {
    public let commonDir: String
    public let rootCommits: Set<String>
    public let remoteURL: String?
    public let remoteResolved: Bool

    public init(commonDir: String, rootCommits: Set<String>, remoteURL: String?, remoteResolved: Bool = true) {
        self.remoteResolved = remoteResolved
        self.commonDir = commonDir
        self.rootCommits = rootCommits
        self.remoteURL = remoteURL
    }
}

public struct GitCommandError: Error, Sendable, Equatable, Codable {
    public let command: String
    public let message: String

    public init(command: String, message: String) {
        self.command = command
        self.message = message
    }
}

public struct GitInspector: Sendable {
    let runner: CommandRunning
    let gitPath: String

    public init(runner: CommandRunning, gitPath: String = "/usr/bin/git") {
        self.runner = runner
        self.gitPath = gitPath
    }

    static let environment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_ASKPASS": "",
        "SSH_ASKPASS": "",
        "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10",
        "GIT_OPTIONAL_LOCKS": "0",
        "LC_ALL": "C",
    ]

    func git(_ repo: URL, _ arguments: [String], timeout: Duration = .seconds(15)) async -> CommandResult {
        await runner.run(gitPath, ["-C", repo.path] + arguments, cwd: repo, environment: Self.environment, timeout: timeout)
    }

    func gitOrThrow(_ repo: URL, _ arguments: [String], timeout: Duration = .seconds(15)) async throws -> Data {
        let result = await git(repo, arguments, timeout: timeout)
        guard result.exitCode == 0, !result.timedOut else {
            throw GitCommandError(
                command: "git " + arguments.joined(separator: " "),
                message: result.timedOut ? "timed out" : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.stdout
    }

    public func fetch(_ repo: URL) async -> FetchOutcome {
        let remotes = await git(repo, ["remote"])
        guard remotes.exitCode == 0, !String(decoding: remotes.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noRemote
        }
        let result = await git(repo, ["fetch", "--quiet"], timeout: .seconds(30))
        if result.timedOut { return .timedOut }
        if result.exitCode == 0 { return .ok(Date()) }
        return .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func status(_ repo: URL) async throws -> GitStatus {
        parsePorcelainV2(try await gitOrThrow(repo, ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--branch", "--show-stash", "--untracked-files=all"]))
    }

    public func worktrees(_ repo: URL) async -> Result<[URL], GitCommandError> {
        do {
            let output = try await gitOrThrow(repo, ["worktree", "list", "--porcelain"])
            return .success(parseWorktreeList(String(decoding: output, as: UTF8.self)))
        } catch let error as GitCommandError {
            return .failure(error)
        } catch {
            return .failure(GitCommandError(command: "git worktree list", message: String(describing: error)))
        }
    }

    public func identity(_ repo: URL) async -> GitIdentity {
        let commonDir = await git(repo, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
        let roots = await git(repo, ["rev-list", "--max-parents=0", "HEAD"])
        let remote = await git(repo, ["config", "--get", "remote.origin.url"])
        func text(_ r: CommandResult) -> String? {
            guard r.exitCode == 0, !r.timedOut else { return nil }
            let value = String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let rootSet = Set((text(roots) ?? "").split(separator: "\n").map(String.init))
        return GitIdentity(
            commonDir: text(commonDir).map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? repo.appendingPathComponent(".git").path,
            rootCommits: rootSet,
            remoteURL: text(remote).map(sanitizeRemoteURL),
            remoteResolved: commonDir.exitCode == 0 && !commonDir.timedOut && !remote.timedOut
                && (remote.exitCode == 0 || remote.exitCode == 1)
        )
    }

    public func trackedFiles(_ repo: URL) async throws -> Set<String> {
        let output = try await gitOrThrow(repo, ["ls-files", "-z"])
        return Set(output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) })
    }
}
