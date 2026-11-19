import Foundation

public struct OpenTerminal: Sendable, Equatable, Codable {
    public let address: String
    public let agent: String?
    public let cwd: String
    public let status: String?

    public init(address: String, agent: String?, cwd: String, status: String?) {
        self.address = address
        self.agent = agent
        self.cwd = cwd
        self.status = status
    }
}

public func parseHcList(_ data: Data) -> [OpenTerminal]? {
    guard let list = try? JSONDecoder().decode(HcTerminalList.self, from: data) else {
        return nil
    }
    return list.terminals.filter { !$0.address.contains("/") }
}

public enum OpenNowState: Sendable, Equatable, Codable {
    case known(Set<ActivityOwner>)
    case unknown(String)
}

public func openNow(runner: CommandRunning, hcPath: String, mapper: ProjectMapper) async -> OpenNowState {
    let result = await runner.run(
        hcPath, ["ls", "--json"], cwd: nil, environment: [:], timeout: .seconds(5)
    )
    if result.timedOut {
        return .unknown("hc ls --json timed out after 5 seconds.")
    }
    let error = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let exitCode = result.exitCode else {
        return .unknown(error.isEmpty ? "Could not launch hc ls --json." : error)
    }
    guard exitCode == 0 else {
        let reason = "hc ls --json exited with code \(exitCode)."
        return .unknown(error.isEmpty ? reason : reason + " " + error)
    }
    guard let terminals = parseHcList(result.stdout) else {
        return .unknown("hc ls --json returned an invalid terminal list.")
    }
    let shells: Set<String> = ["zsh", "bash", "sh", "fish", "nu"]
    var owners: Set<ActivityOwner> = []
    for terminal in terminals {
        guard let agent = terminal.agent?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !agent.isEmpty, !shells.contains(agent) else {
            continue
        }
        owners.insert(mapper.map(terminal.cwd))
    }
    return .known(owners)
}

private struct HcTerminalList: Decodable {
    let terminals: [OpenTerminal]
}
