import Foundation
import Testing
@testable import ZeigarnikCore

private struct GhRunner: CommandRunning {
    let exitCode: Int32
    let output: String
    let calls = Recorder<[String]>()
    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        await calls.add(arguments)
        return CommandResult(exitCode: exitCode, stdout: Data(output.utf8), stderr: "", timedOut: false)
    }
}

actor Recorder<T: Sendable> {
    private(set) var items: [T] = []
    func add(_ item: T) { items.append(item) }
}

private func http(_ status: Int?, _ seen: Recorder<URL>) -> @Sendable (URL) async -> Int? {
    { url in await seen.add(url); return status }
}

@Suite struct RepoVisibilityTests {
    @Test func remoteFormsParseToHostAndPath() {
        #expect(parseRemote("git@github.com:acme/tool.git") == RemoteRepo(host: "github.com", path: "acme/tool"))
        #expect(parseRemote("https://github.com/acme/tool") == RemoteRepo(host: "github.com", path: "acme/tool"))
        #expect(parseRemote("https://GitHub.com/acme/tool.git/") == RemoteRepo(host: "github.com", path: "acme/tool"))
        #expect(parseRemote("ssh://git@github.com/acme/tool.git") == RemoteRepo(host: "github.com", path: "acme/tool"))
        #expect(parseRemote("https://gitlab.com/group/sub/tool.git") == RemoteRepo(host: "gitlab.com", path: "group/sub/tool"))
        #expect(parseRemote("git@bitbucket.org:acme/tool.git") == RemoteRepo(host: "bitbucket.org", path: "acme/tool"))
        #expect(parseRemote("https://github.com/acme") == nil)
        #expect(parseRemote("/Users/example/repos/tool") == nil)
        #expect(parseRemote("file:///Users/example/repos/tool.git") == nil)
        #expect(parseRemote("https://github.com/acme/../../users/x") == nil)
        #expect(parseRemote("git@github.com:acme/./tool.git") == nil)
    }

    @Test func ghAnswerWinsForGitHub() async {
        let runner = GhRunner(exitCode: 0, output: "PUBLIC\n")
        let seen = Recorder<URL>()
        let probe = NetworkVisibilityProbe(runner: runner, ghPath: "/opt/gh", httpStatus: http(404, seen))
        #expect(await probe.visibility(of: RemoteRepo(host: "github.com", path: "acme/tool")) == .public)
        #expect(await runner.calls.items == [["repo", "view", "acme/tool", "--json", "visibility", "--jq", ".visibility"]])
        #expect(await seen.items.isEmpty)
        let privateRunner = GhRunner(exitCode: 0, output: "PRIVATE\n")
        let probe2 = NetworkVisibilityProbe(runner: privateRunner, ghPath: "/opt/gh", httpStatus: http(200, seen))
        #expect(await probe2.visibility(of: RemoteRepo(host: "github.com", path: "acme/tool")) == .private)
    }

    @Test func ghFailureFallsBackToTheAPI() async {
        let seen = Recorder<URL>()
        let probe = NetworkVisibilityProbe(runner: GhRunner(exitCode: 1, output: ""), ghPath: "/opt/gh", httpStatus: http(404, seen))
        #expect(await probe.visibility(of: RemoteRepo(host: "github.com", path: "acme/tool")) == .private)
        #expect(await seen.items == [URL(string: "https://api.github.com/repos/acme/tool")!])
    }

    @Test func withoutGhTheAPIDecides() async {
        let seen = Recorder<URL>()
        let runner = GhRunner(exitCode: 0, output: "PRIVATE")
        let probe = NetworkVisibilityProbe(runner: runner, ghPath: nil, httpStatus: http(200, seen))
        #expect(await probe.visibility(of: RemoteRepo(host: "github.com", path: "acme/tool")) == .public)
        #expect(await runner.calls.items.isEmpty)
    }

    @Test func rateLimitsAndNetworkErrorsAreUnknown() async {
        let seen = Recorder<URL>()
        for status in [403, 429, 500, nil] as [Int?] {
            let probe = NetworkVisibilityProbe(runner: GhRunner(exitCode: 1, output: ""), ghPath: nil, httpStatus: http(status, seen))
            #expect(await probe.visibility(of: RemoteRepo(host: "github.com", path: "acme/tool")) == .unknown)
        }
    }

    @Test func gitLabUsesItsProjectsAPIAndNeverGh() async {
        let seen = Recorder<URL>()
        let runner = GhRunner(exitCode: 0, output: "PRIVATE")
        let probe = NetworkVisibilityProbe(runner: runner, ghPath: "/opt/gh", httpStatus: http(200, seen))
        #expect(await probe.visibility(of: RemoteRepo(host: "gitlab.com", path: "group/sub/tool")) == .public)
        #expect(await seen.items.map(\.absoluteString) == ["https://gitlab.com/api/v4/projects/group%2Fsub%2Ftool"])
        #expect(await runner.calls.items.isEmpty)
    }

    @Test func otherHostsAreUnknownWithoutNetwork() async {
        let seen = Recorder<URL>()
        let runner = GhRunner(exitCode: 0, output: "PUBLIC")
        let probe = NetworkVisibilityProbe(runner: runner, ghPath: "/opt/gh", httpStatus: http(200, seen))
        #expect(await probe.visibility(of: RemoteRepo(host: "bitbucket.org", path: "acme/tool")) == .unknown)
        #expect(await seen.items.isEmpty)
        #expect(await runner.calls.items.isEmpty)
    }

    @Test func visibilityReachesTheRowAndCanBeCleared() throws {
        let store = try Store.inMemory()
        let id = try store.upsertProject(resolution: .new, path: "/r/tool", displayName: "tool", identity: nil)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first?.visibility == nil)
        let at = Date(timeIntervalSince1970: 1_763_550_000)
        try store.writeVisibility(projectId: id, VisibilityCheck(visibility: .public, checkedAt: at))
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first?.visibility == .public)
        #expect(try store.visibilityChecks()[id] == VisibilityCheck(visibility: .public, checkedAt: at))
        try store.writeVisibility(projectId: id, nil)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first?.visibility == nil)
    }
}
