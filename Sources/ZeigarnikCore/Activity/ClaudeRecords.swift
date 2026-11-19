import Foundation

public func parseClaudeTranscriptLine(_ line: Data) -> LineOutcome<OwnerMessage> {
    guard let json = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]) else {
        return .malformed
    }
    guard let record = json as? [String: Any],
          !isAutomatedClaudeRecord(record),
          record["type"] as? String == "user",
          record["isMeta"] as? Bool != true,
          record["isCompactSummary"] as? Bool != true,
          let message = record["message"] as? [String: Any],
          let content = activityContent(message["content"]),
          !content.hasToolResult,
          isClaudeOwnerContent(content.text, hasImage: content.hasImage),
          let sessionId = record["sessionId"] as? String, !sessionId.isEmpty,
          let timestamp = activityTimestamp(record["timestamp"]) else {
        return .skipped
    }
    return .record(OwnerMessage(
        agent: .claude,
        sessionId: sessionId,
        timestamp: timestamp,
        cwd: record["cwd"] as? String,
        source: .transcript
    ))
}

public func claudeSession(fromLine line: Data) -> (sessionId: String, cwd: String, timestamp: Date?, delegated: Bool)? {
    guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let sessionId = record["sessionId"] as? String, !sessionId.isEmpty,
          let cwd = record["cwd"] as? String, !cwd.isEmpty else {
        return nil
    }
    return (sessionId, cwd, activityTimestamp(record["timestamp"]), isAutomatedClaudeRecord(record))
}

private func isAutomatedClaudeRecord(_ record: [String: Any]) -> Bool {
    (record["entrypoint"] as? String)?.hasPrefix("sdk-") == true
}

public func parseClaudeHistoryLine(_ line: Data) -> OwnerMessage? {
    guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
          let text = record["display"] as? String,
          isClaudeOwnerContent(text, hasImage: false),
          let milliseconds = record["timestamp"] as? Double, milliseconds.isFinite,
          let project = record["project"] as? String, !project.isEmpty else {
        return nil
    }
    let sessionId = record["sessionId"] as? String
    return OwnerMessage(
        agent: .claude,
        sessionId: sessionId.flatMap { $0.isEmpty ? nil : $0 } ?? "history:" + project,
        timestamp: Date(timeIntervalSince1970: milliseconds / 1000),
        cwd: project,
        source: .history
    )
}

public func isRelayedAgentText(_ text: String) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.hasPrefix("<hc from=") || text.hasPrefix("<agent-message")
}

private func isClaudeOwnerContent(_ text: String, hasImage: Bool) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let excludedPrefixes = [
        "<task-notification>", "<local-command-stdout>", "<bash-stdout>",
        "<system-reminder>", "<local-command-caveat>",
    ]
    return !isRelayedAgentText(text)
        && !excludedPrefixes.contains(where: { text.hasPrefix($0) })
        && (!text.isEmpty || hasImage)
}
