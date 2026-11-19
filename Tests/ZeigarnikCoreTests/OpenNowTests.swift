import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("OpenNow")
struct OpenNowTests {
    private var fixtureData: Data { Data(fixture("hc-ls.json").utf8) }

    private var mapper: ProjectMapper {
        ProjectMapper(
            projects: [(id: "alpha", path: "/synthetic/projects/alpha")],
            home: "/synthetic/home",
            workspaceRoot: "/synthetic/projects"
        )
    }

    private var expectedOwners: Set<ActivityOwner> {
        [.project("alpha"), .other("~/Desktop/beta")]
    }

    @Test func excludesRemoteMachineTerminals() throws {
        let terminals = try #require(parseHcList(fixtureData))
        #expect(terminals.map(\.address) == ["t4h", "t50", "t51", "t60", "t61"])
        #expect(terminals.first == OpenTerminal(
            address: "t4h", agent: "claude-code", cwd: "/synthetic/projects/alpha/src", status: "working"
        ))
        let shell = try #require(terminals.first { $0.address == "t60" })
        #expect(shell.agent == "zsh")
        #expect(shell.status == nil)
        let unassigned = try #require(terminals.first { $0.address == "t61" })
        #expect(unassigned.agent == nil)
        #expect(unassigned.cwd == "/synthetic/home/unassigned")
    }

    @Test(arguments: ["zsh", "bash", "sh", "fish", "nu"])
    func onlyAgentTerminalsCount(shell: String) async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        var terminals = try #require(object["terminals"] as? [[String: Any]])
        let shellIndex = try #require(terminals.firstIndex { $0["address"] as? String == "t60" })
        terminals[shellIndex]["agent"] = shell
        object["terminals"] = terminals
        let data = try JSONSerialization.data(withJSONObject: object)
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: data, stderr: "", timedOut: false))

        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        #expect(state == .known(expectedOwners))
    }

    @Test func failureIsUnknownNotEmpty() async {
        let runner = HcRunner(result: CommandResult(
            exitCode: 1, stdout: fixtureData, stderr: "Synthetic hc failure", timedOut: false
        ))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        if case .unknown(let reason) = state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("An unsuccessful command must produce .unknown even when stdout contains terminals")
        }
    }

    @Test func invalidJSONIsUnknown() async {
        let invalid = Data("{".utf8)
        #expect(parseHcList(invalid) == nil)
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: invalid, stderr: "", timedOut: false))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        if case .unknown(let reason) = state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Invalid JSON must produce .unknown")
        }
    }

    @Test func mapsToOwners() async throws {
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: fixtureData, stderr: "", timedOut: false))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        #expect(state == .known(expectedOwners))
        let calls = await runner.calls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.executable == "/synthetic/bin/hc")
        #expect(call.arguments == ["ls", "--json"])
        #expect(call.timeout == .seconds(5))
    }

    @Test func timedOutCommandIsUnknown() async {
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: fixtureData, stderr: "", timedOut: true))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        if case .unknown(let reason) = state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("A timed-out command must produce .unknown")
        }
    }

    @Test func launchFailureIsUnknown() async {
        let runner = HcRunner(result: CommandResult(exitCode: nil, stdout: fixtureData, stderr: "Synthetic launch failure", timedOut: false))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        if case .unknown(let reason) = state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("A launch failure must produce .unknown")
        }
    }

    @Test func successfulEmptyListIsKnownEmpty() async throws {
        let data = Data("{\"hidden_finished\":0,\"machines\":[],\"terminals\":[]}".utf8)
        let terminals = try #require(parseHcList(data))
        #expect(terminals.isEmpty)
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: data, stderr: "", timedOut: false))
        #expect(await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper) == .known([]))
    }

    @Test(arguments: ["{}", "[]", "{\"terminals\":\"invalid\"}"])
    func invalidEnvelopeIsUnknown(json: String) async {
        let data = Data(json.utf8)
        #expect(parseHcList(data) == nil)
        let runner = HcRunner(result: CommandResult(exitCode: 0, stdout: data, stderr: "", timedOut: false))
        let state = await openNow(runner: runner, hcPath: "/synthetic/bin/hc", mapper: mapper)
        if case .unknown(let reason) = state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("An invalid terminal-list envelope must produce .unknown")
        }
    }

    @Test func publicModelsRoundTripAsJSON() throws {
        let terminal = OpenTerminal(address: "t61", agent: nil, cwd: "/synthetic/home/unassigned", status: nil)
        let terminalData = try JSONEncoder().encode(terminal)
        #expect(try JSONDecoder().decode(OpenTerminal.self, from: terminalData) == terminal)
        for state in [OpenNowState.known(expectedOwners), .unknown("Synthetic failure")] {
            let data = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(OpenNowState.self, from: data) == state)
        }
    }
}

private struct HcCall: Sendable {
    let executable: String
    let arguments: [String]
    let timeout: Duration
}

private actor HcRunner: CommandRunning {
    private let result: CommandResult
    private(set) var calls: [HcCall] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        calls.append(HcCall(executable: executable, arguments: arguments, timeout: timeout))
        return result
    }
}
