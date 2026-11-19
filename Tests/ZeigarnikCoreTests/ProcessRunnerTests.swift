import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test func capturesStdoutAndExitCode() async {
        let r = await ProcessRunner().run("/bin/echo", ["zeigarnik"], cwd: nil, environment: [:], timeout: .seconds(5))
        #expect(r.exitCode == 0)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "zeigarnik\n")
        #expect(!r.timedOut)
    }

    @Test func reportsNonZeroExit() async {
        let r = await ProcessRunner().run("/usr/bin/false", [], cwd: nil, environment: [:], timeout: .seconds(5))
        #expect(r.exitCode == 1)
        #expect(!r.timedOut)
    }

    @Test func killsOnTimeout() async {
        let start = Date()
        let r = await ProcessRunner().run("/bin/sleep", ["5"], cwd: nil, environment: [:], timeout: .milliseconds(200))
        #expect(r.timedOut)
        #expect(r.exitCode == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// A command that finished keeps its exit code even when a helper it started still holds the output pipe.
    @Test func helperLeftInTheGroupDoesNotTurnSuccessIntoTimeout() async {
        let start = Date()
        let r = await ProcessRunner().run("/bin/sh", ["-c", "sleep 30 & echo done"], cwd: nil, environment: [:], timeout: .seconds(4))
        #expect(r.exitCode == 0)
        #expect(!r.timedOut)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "done\n")
        #expect(Date().timeIntervalSince(start) < 2)
    }

    /// A helper in its own session (an ssh ControlPersist master, for example) is out of reach; the wait for it is bounded.
    @Test func helperInAnotherSessionDoesNotTurnSuccessIntoTimeout() async {
        let start = Date()
        let script = "use POSIX; fork and exit; POSIX::setsid(); sleep 30"
        let r = await ProcessRunner().run("/usr/bin/perl", ["-e", script], cwd: nil, environment: [:], timeout: .seconds(9))
        #expect(r.exitCode == 0)
        #expect(!r.timedOut)
        #expect(Date().timeIntervalSince(start) < 8)
    }

    @Test func largeOutputDoesNotDeadlock() async {
        let r = await ProcessRunner().run("/bin/dd", ["if=/dev/zero", "bs=1024", "count=300"], cwd: nil, environment: [:], timeout: .seconds(10))
        #expect(r.exitCode == 0)
        #expect(r.stdout.count == 307_200)
    }

    @Test func passesEnvironment() async {
        let r = await ProcessRunner().run("/usr/bin/env", [], cwd: nil, environment: ["ZG_TEST": "1"], timeout: .seconds(5))
        #expect(String(decoding: r.stdout, as: UTF8.self).contains("ZG_TEST=1"))
    }

    @Test func usesWorkingDirectory() async {
        let r = await ProcessRunner().run("/bin/pwd", [], cwd: URL(fileURLWithPath: "/tmp"), environment: [:], timeout: .seconds(5))
        #expect(String(decoding: r.stdout, as: UTF8.self).hasSuffix("tmp\n"))
    }
}
