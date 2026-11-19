import Foundation
import Darwin
import Testing
@testable import ZeigarnikCore

private actor GitEnvironmentRecorder: CommandRunning {
    var environments: [[String: String]] = []

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        environments.append(environment)
        return CommandResult(exitCode: 0, stdout: Data("origin\n".utf8), stderr: "", timedOut: false)
    }
}

private struct HangingFetchRunner: CommandRunning {
    let script: URL

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        if arguments.contains("fetch") {
            return await ProcessRunner().run("/bin/sh", [script.path], cwd: script.deletingLastPathComponent(), environment: environment, timeout: .milliseconds(400))
        }
        return CommandResult(exitCode: 0, stdout: Data("origin\n".utf8), stderr: "", timedOut: false)
    }
}

@Suite("GitProcessSafety")
struct GitProcessSafetyTests {
    @Test func C8_everyGitOperationDisablesAskpass() async throws {
        let runner = GitEnvironmentRecorder()
        let inspector = GitInspector(runner: runner)
        let repo = URL(fileURLWithPath: "/synthetic/orbit")
        _ = await inspector.identity(repo)
        _ = await inspector.worktrees(repo)
        _ = try await inspector.status(repo)
        _ = try await inspector.history(repo)
        _ = try await inspector.trackedFiles(repo)
        _ = await inspector.fetch(repo)
        let environments = await runner.environments
        #expect(environments.count >= 9)
        for environment in environments {
            #expect(environment["GIT_ASKPASS"] == "")
            #expect(environment["SSH_ASKPASS"] == "")
            #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
            #expect(environment["GIT_SSH_COMMAND"] == "ssh -o BatchMode=yes -o ConnectTimeout=10")
        }
    }

    @Test func C8_fetchTimeoutKillsHelperProcess() async throws {
        let dir = try makeTempDir()
        let script = dir.appendingPathComponent("hanging-fetch.sh")
        try Data("/bin/sleep 30 &\nchild=$!\nprintf '%s' \"$child\" > child.pid\nwait\n".utf8).write(to: script)
        let start = ContinuousClock.now
        let result = await GitInspector(runner: HangingFetchRunner(script: script)).fetch(dir)
        #expect(result == .timedOut)
        #expect(start.duration(to: .now) < .seconds(3))
        let text = try String(contentsOf: dir.appendingPathComponent("child.pid"), encoding: .utf8)
        let pid = try #require(Int32(text))
        defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
        for _ in 0..<50 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
