import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("ClaudeRecords")
struct ClaudeRecordsTests {
    @Test func sdkEntrypointUserLineIsSkipped() throws {
        let line = fixtureLine("claude-transcript.jsonl", tag: "sdk")
        try #require(!line.isEmpty)
        if case .skipped = parseClaudeTranscriptLine(line) {
        } else {
            Issue.record("An sdk-cli user record must be skipped as automated activity")
        }
    }

    @Test func cliEntrypointUserLineIsRecorded() throws {
        let line = fixtureLine("claude-transcript.jsonl", tag: "cli-entry")
        try #require(!line.isEmpty)
        if case .record(let message) = parseClaudeTranscriptLine(line) {
            #expect(message == OwnerMessage(
                agent: .claude, sessionId: "s-cli", timestamp: isoDate("2026-11-18T17:53:11.035Z"),
                cwd: "/synthetic/projects/entrypoints", source: .transcript
            ))
        } else {
            Issue.record("A cli user record must count as owner activity")
        }
    }

    @Test func unknownEntrypointCountsAsOwner() throws {
        let line = fixtureLine("claude-transcript.jsonl", tag: "desktop-entry")
        try #require(!line.isEmpty)
        if case .record(let message) = parseClaudeTranscriptLine(line) {
            #expect(message == OwnerMessage(
                agent: .claude, sessionId: "s-desktop", timestamp: isoDate("2026-11-18T17:53:11.035Z"),
                cwd: "/synthetic/projects/entrypoints", source: .transcript
            ))
        } else {
            Issue.record("A non-sdk entrypoint must count as owner activity")
        }
    }

    @Test func sessionFromSdkLineIsDelegated() throws {
        let sdk = try #require(claudeSession(fromLine: fixtureLine("claude-transcript.jsonl", tag: "sdk")))
        let cli = try #require(claudeSession(fromLine: fixtureLine("claude-transcript.jsonl", tag: "cli-entry")))
        #expect(sdk.sessionId == "s-sdk")
        #expect(sdk.cwd == "/synthetic/projects/entrypoints")
        #expect(sdk.timestamp == isoDate("2026-11-18T17:53:11.035Z"))
        #expect(sdk.delegated)
        #expect(!cli.delegated)
    }

    @Test(arguments: [
        ("plain", true), ("bash-input", true), ("slash-command", true),
        ("image", true), ("interrupted", true), ("tool-result", false),
        ("is-meta", false), ("compact-summary", false), ("task-notification", false),
        ("local-command-stdout", false), ("bash-stdout", false), ("hc-relay", false),
        ("assistant", false), ("agent-handback", false),
    ])
    func transcriptFilter(caseName: String, counted: Bool) {
        let line = fixtureLine("claude-transcript.jsonl", tag: caseName)
        #expect(!line.isEmpty)
        switch parseClaudeTranscriptLine(line) {
        case .record(let message):
            #expect(counted)
            #expect(message == OwnerMessage(
                agent: .claude,
                sessionId: "s-claude",
                timestamp: isoDate("2026-11-18T17:53:11.035Z"),
                cwd: "/Users/example/Documents/Projects/02_Products/orbit",
                source: .transcript
            ))
        case .skipped:
            #expect(!counted)
        case .malformed:
            Issue.record("Valid transcript fixture was reported malformed: \(caseName)")
        }
    }

    @Test func historyLineParsesMillisecondsAndProject() throws {
        let message = try #require(parseClaudeHistoryLine(fixtureLine("claude-history.jsonl", tag: "plain")))
        #expect(message == OwnerMessage(
            agent: .claude,
            sessionId: "s-claude-history",
            timestamp: isoDate("2025-10-02T04:43:17.429Z"),
            cwd: "/Users/example/Desktop",
            source: .history
        ))
    }

    @Test func historyRelayIsExcluded() {
        let line = fixtureLine("claude-history.jsonl", tag: "hc-relay")
        #expect(!line.isEmpty)
        #expect(parseClaudeHistoryLine(line) == nil)
    }

    @Test func historyWithoutSessionUsesProjectFallback() throws {
        let message = try #require(parseClaudeHistoryLine(fixtureLine("claude-history.jsonl", tag: "missing-session")))
        #expect(message.sessionId == "history:/Users/example/Desktop")
        #expect(message.cwd == "/Users/example/Desktop")
        #expect(message.timestamp == isoDate("2025-10-02T04:43:17.429Z"))
        #expect(message.agent == .claude)
        #expect(message.source == .history)
    }

    @Test func malformedIsDistinctFromSkipped() {
        if case .malformed = parseClaudeTranscriptLine(Data("{".utf8)) {
        } else {
            Issue.record("Invalid JSON must produce .malformed")
        }
        let line = fixtureLine("claude-transcript.jsonl", tag: "tool-result")
        #expect(!line.isEmpty)
        if case .skipped = parseClaudeTranscriptLine(line) {
        } else {
            Issue.record("A valid tool result must produce .skipped")
        }
    }

    @Test(arguments: [
        ("<hc from=\"t4x\">Synthetic relay.</hc>", true),
        ("<agent-message>Synthetic hand-back.</agent-message>", true),
        ("Inspect the synthetic sample.", false),
        ("Explain the <hc from= marker.", false),
    ])
    func relayTextIsRecognized(text: String, isRelay: Bool) {
        #expect(isRelayedAgentText(text) == isRelay)
    }

    @Test func sessionObservationIncludesAssistantActivity() throws {
        let observation = try #require(claudeSession(fromLine: fixtureLine("claude-transcript.jsonl", tag: "assistant")))
        #expect(observation.sessionId == "s-claude")
        #expect(observation.cwd == "/Users/example/Documents/Projects/02_Products/orbit")
        #expect(observation.timestamp == isoDate("2026-11-18T17:53:11.035Z"))
    }

    @Test func sessionObservationPreservesUntimedActivity() throws {
        let observation = try #require(claudeSession(fromLine: fixtureLine("claude-transcript.jsonl", tag: "untimed-session")))
        #expect(observation.sessionId == "s-untimed")
        #expect(observation.cwd == "/Users/example/Desktop")
        #expect(observation.timestamp == nil)
    }

    @Test func malformedSessionObservationIsNil() {
        #expect(claudeSession(fromLine: Data("{".utf8)) == nil)
    }
}
