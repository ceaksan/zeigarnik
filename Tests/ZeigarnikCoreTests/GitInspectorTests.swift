import Foundation
import Testing
@testable import ZeigarnikCore

@discardableResult
func runGit(_ repo: URL, _ args: [String]) async -> CommandResult {
    await ProcessRunner().run("/usr/bin/git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main"] + args, cwd: repo, environment: ["GIT_TERMINAL_PROMPT": "0"], timeout: .seconds(30))
}

func makeRepo(commit: Bool = true) async throws -> URL {
    let repo = try makeTempDir()
    await runGit(repo, ["init", "-q"])
    if commit {
        try Data("hello\n".utf8).write(to: repo.appendingPathComponent("README.md"))
        await runGit(repo, ["add", "README.md"])
        await runGit(repo, ["commit", "-q", "-m", "init"])
    }
    return repo
}

@Suite("GitInspector")
struct GitInspectorTests {
    let inspector = GitInspector(runner: ProcessRunner())

    @Test func statusCountsUntrackedFilesNotDirectories() async throws {
        let repo = try await makeRepo()
        let u = repo.appendingPathComponent("u")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        for name in ["a", "b", "c"] { try Data("x".utf8).write(to: u.appendingPathComponent(name)) }
        try Data("changed\n".utf8).write(to: repo.appendingPathComponent("README.md"))
        let status = try await inspector.status(repo)
        #expect(status.untracked == 3)
        #expect(status.changed == 1)
        #expect(status.branch == "main")
    }

    @Test func worktreesIncludeNestedCheckout() async throws {
        let repo = try await makeRepo()
        await runGit(repo, ["worktree", "add", "-q", ".wt/x", "-b", "x"])
        let worktrees = try #require(try? await inspector.worktrees(repo).get())
        #expect(worktrees.count == 2)
        #expect(worktrees.map(\.lastPathComponent).contains("x"))
    }

    @Test func identityHasRootCommitsAndCommonDir() async throws {
        let repo = try await makeRepo()
        let identity = await inspector.identity(repo)
        #expect(identity.rootCommits.count == 1)
        #expect(identity.commonDir.hasSuffix("/.git"))
        let unborn = try await makeRepo(commit: false)
        #expect(await inspector.identity(unborn).rootCommits.isEmpty)
    }

    @Test func identityStripsCredentials() async throws {
        let repo = try await makeRepo()
        await runGit(repo, ["remote", "add", "origin", "https://u:p@example.com/r.git"])
        #expect(await inspector.identity(repo).remoteURL == "https://example.com/r.git")
    }

    @Test func fetchToUnreachableRemoteFailsFast() async throws {
        let repo = try await makeRepo()
        await runGit(repo, ["remote", "add", "origin", "https://127.0.0.1:9/none.git"])
        let start = Date()
        let outcome = await inspector.fetch(repo)
        switch outcome {
        case .failed, .timedOut: break
        default: Issue.record("expected failure, got \(outcome)")
        }
        #expect(Date().timeIntervalSince(start) < 31)
    }

    @Test func fetchWithoutRemoteIsNoRemote() async throws {
        let repo = try await makeRepo()
        #expect(await inspector.fetch(repo) == .noRemote)
    }

    @Test func trackedFilesListsIndex() async throws {
        let repo = try await makeRepo()
        #expect(try await inspector.trackedFiles(repo) == ["README.md"])
    }
}
