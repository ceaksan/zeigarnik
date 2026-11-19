import Foundation

public struct CodexSessionHeader: Sendable, Equatable, Codable {
    public let sessionId: String
    public let cwd: String?
    public let isDelegated: Bool
    public let startedAt: Date?

    public init(sessionId: String, cwd: String?, isDelegated: Bool, startedAt: Date?) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.isDelegated = isDelegated
        self.startedAt = startedAt
    }
}

public func parseCodexHeader(firstLines: [Data]) -> CodexSessionHeader? {
    let records = firstLines.compactMap { line in
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }
    if let record = records.first(where: { $0["type"] as? String == "session_meta" }),
       let payload = record["payload"] as? [String: Any],
       let sessionId = (payload["id"] as? String) ?? (payload["session_id"] as? String),
       !sessionId.isEmpty {
        let source = payload["source"] as? [String: Any]
        let delegated = payload["source"] as? String == "exec"
            || source?["subagent"] != nil
            || payload["originator"] as? String == "codex_exec"
        return CodexSessionHeader(
            sessionId: sessionId,
            cwd: payload["cwd"] as? String,
            isDelegated: delegated,
            startedAt: activityTimestamp(payload["timestamp"]) ?? activityTimestamp(record["timestamp"])
        )
    }
    guard let record = records.first, record["type"] == nil,
          let sessionId = record["id"] as? String, !sessionId.isEmpty else {
        return nil
    }
    return CodexSessionHeader(
        sessionId: sessionId,
        cwd: legacyCodexCwd(in: records),
        isDelegated: false,
        startedAt: activityTimestamp(record["timestamp"])
    )
}

public func parseCodexRolloutLine(_ line: Data, header: CodexSessionHeader) -> LineOutcome<OwnerMessage> {
    guard let json = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]) else {
        return .malformed
    }
    guard let record = json as? [String: Any], !header.isDelegated else {
        return .skipped
    }
    let message: [String: Any]
    switch record["type"] as? String {
    case "response_item":
        guard let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "message" else { return .skipped }
        message = payload
    case "message":
        message = record
    default:
        return .skipped
    }
    guard message["role"] as? String == "user",
          let content = activityContent(message["content"]),
          !content.hasToolResult,
          isCodexOwnerContent(content.text, hasImage: content.hasImage),
          let timestamp = activityTimestamp(record["timestamp"]) else {
        return .skipped
    }
    return .record(OwnerMessage(
        agent: .codex,
        sessionId: header.sessionId,
        timestamp: timestamp,
        cwd: header.cwd,
        source: .transcript
    ))
}

public struct CodexHistoryEntry: Sendable, Equatable {
    public let sessionId: String
    public let timestamp: Date
    public let isRelay: Bool

    public init(sessionId: String, timestamp: Date, isRelay: Bool) {
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.isRelay = isRelay
    }
}

public func parseCodexHistoryLine(_ line: Data) -> LineOutcome<CodexHistoryEntry> {
    guard let json = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]) else {
        return .malformed
    }
    guard let record = json as? [String: Any],
          let sessionId = record["session_id"] as? String, !sessionId.isEmpty,
          let seconds = record["ts"] as? Double, seconds.isFinite,
          let text = record["text"] as? String else {
        return .skipped
    }
    return .record(CodexHistoryEntry(
        sessionId: sessionId,
        timestamp: Date(timeIntervalSince1970: seconds),
        isRelay: isRelayedAgentText(text)
    ))
}

private func isCodexOwnerContent(_ text: String, hasImage: Bool) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let excludedPrefixes = [
        "# AGENTS.md", "<environment_context>", "<codex_internal_context>",
        "<recommended_plugins>",
    ]
    return !isRelayedAgentText(text)
        && !excludedPrefixes.contains(where: { text.hasPrefix($0) })
        && (!text.isEmpty || hasImage)
}

private func legacyCodexCwd(in records: [[String: Any]]) -> String? {
    for record in records {
        guard record["type"] as? String == "message",
              record["role"] as? String == "user",
              let content = activityContent(record["content"]),
              let opening = content.text.range(of: "<environment_context>"),
              let closing = content.text.range(of: "</environment_context>", range: opening.upperBound..<content.text.endIndex) else {
            continue
        }
        let environment = content.text[opening.upperBound..<closing.lowerBound]
        guard let cwdStart = environment.range(of: "<cwd>"),
              let cwdEnd = environment.range(of: "</cwd>", range: cwdStart.upperBound..<environment.endIndex) else {
            continue
        }
        let cwd = environment[cwdStart.upperBound..<cwdEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        if !cwd.isEmpty { return cwd }
    }
    return nil
}
