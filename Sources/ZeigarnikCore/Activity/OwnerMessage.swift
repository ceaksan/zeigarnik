import Foundation

public enum Agent: String, Sendable, Codable {
    case claude, codex
}

public enum MessageSource: String, Sendable, Codable {
    case history, transcript
}

public struct OwnerMessage: Sendable, Hashable, Codable {
    public let agent: Agent
    public let sessionId: String
    public let timestamp: Date
    public let cwd: String?
    public let source: MessageSource

    public init(agent: Agent, sessionId: String, timestamp: Date, cwd: String?, source: MessageSource) {
        self.agent = agent
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.cwd = cwd
        self.source = source
    }
}

public enum LineOutcome<T: Sendable>: Sendable {
    case record(T)
    case skipped
    case malformed
}

nonisolated(unsafe) private let fractionalISO8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
nonisolated(unsafe) private let plainISO8601 = ISO8601DateFormatter()

func activityTimestamp(_ value: Any?) -> Date? {
    guard let text = value as? String else { return nil }
    return fractionalISO8601.date(from: text) ?? plainISO8601.date(from: text)
}

func activityContent(_ value: Any?) -> (text: String, hasImage: Bool, hasToolResult: Bool)? {
    if let text = value as? String {
        return (text, false, false)
    }
    guard let blocks = value as? [[String: Any]] else { return nil }
    let text = blocks.compactMap { block -> String? in
        guard let type = block["type"] as? String,
              ["text", "input_text", "output_text"].contains(type) else { return nil }
        return block["text"] as? String
    }.joined(separator: "\n")
    let hasImage = blocks.contains { block in
        guard let type = block["type"] as? String else { return false }
        return type == "image" || type == "input_image"
    }
    let hasToolResult = blocks.contains { $0["type"] as? String == "tool_result" }
    return (text, hasImage, hasToolResult)
}
