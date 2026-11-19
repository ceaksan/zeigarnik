import Foundation

/// Starts a shell in a new herdr terminal at `path`. Returns nil on success, otherwise a message for the UI.
public func openInHerdr(runner: CommandRunning, hcPath: String, path: String) async -> String? {
    let result = await runner.run(hcPath, ["run", "--bg", "--no-parent", "--cwd", path], cwd: nil, environment: [:], timeout: .seconds(10))
    if result.timedOut { return "Could not open in herdr: hc did not answer in 10 seconds." }
    guard result.exitCode == 0 else {
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Could not open in herdr: " + (detail.isEmpty ? "hc exited with code \(result.exitCode.map(String.init) ?? "?")." : detail)
    }
    return nil
}
