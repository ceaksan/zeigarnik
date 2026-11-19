import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("CodexRecords")
struct CodexRecordsTests {
    private var modernSession: CodexSessionHeader {
        CodexSessionHeader(
            sessionId: "s-modern",
            cwd: "/Users/example/Documents/Projects/02_Products/orbit",
            isDelegated: false,
            startedAt: isoDate("2026-11-18T17:53:11.035Z")
        )
    }

    @Test func modernHeader() {
        let lines = fixtureLines("codex-rollout-modern.jsonl")
        #expect(!lines.isEmpty)
        #expect(parseCodexHeader(firstLines: lines) == modernSession)
    }

    @Test(arguments: [
        "<codex_internal_context source=\"x\">Synthetic context.</codex_internal_context>",
        "<codex_internal_context\nsource=\"x\">Synthetic context.</codex_internal_context>",
        "<user_instructions>Synthetic instructions.</user_instructions>",
        "<user_instructions source=\"x\">Synthetic instructions.</user_instructions>",
    ])
    func C6_instructionBlocksAreNotOwnerMessages(_ text: String) throws {
        for legacy in [false, true] {
            let message: [String: Any] = ["type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]
            var row: [String: Any] = legacy ? message : ["type": "response_item", "payload": message]
            row["timestamp"] = "2026-01-01T10:00:00Z"
            let data = try JSONSerialization.data(withJSONObject: row)
            guard case .skipped = parseCodexRolloutLine(data, header: modernSession) else {
                Issue.record("Instruction blocks must not count as owner messages")
                continue
            }
        }
    }

    @Test(arguments: [
        ("codex-rollout-exec.jsonl", "s-exec"),
        ("codex-rollout-subagent.jsonl", "s-subagent"),
    ])
    func execAndSubagentAreDelegated(fixtureName: String, sessionId: String) {
        let expectedHeader = CodexSessionHeader(
            sessionId: sessionId,
            cwd: "/Users/example/Documents/Projects/02_Products/orbit",
            isDelegated: true,
            startedAt: isoDate("2026-11-18T17:53:11.035Z")
        )
        #expect(parseCodexHeader(firstLines: fixtureLines(fixtureName)) == expectedHeader)
        let line = fixtureLine(fixtureName, tag: "plain")
        #expect(!line.isEmpty)
        if case .skipped = parseCodexRolloutLine(line, header: expectedHeader) {
        } else {
            Issue.record("Delegated user messages must produce .skipped")
        }
    }

    @Test func legacyHeaderTakesCwdFromEnvironmentContext() {
        let lines = fixtureLines("codex-rollout-legacy.jsonl")
        #expect(lines.count == 4)
        #expect(parseCodexHeader(firstLines: lines) == CodexSessionHeader(
            sessionId: "s-legacy",
            cwd: "/Users/example/Desktop/site-v4.0",
            isDelegated: false,
            startedAt: isoDate("2025-09-03T10:39:35.000Z")
        ))
    }

    @Test(arguments: [
        "plain", "image", "question-reply", "user-shell", "agents-md",
        "environment-context", "internal-context", "recommended-plugins", "hc-relay", "assistant",
    ])
    func rolloutFilter(caseName: String) {
        let counted = ["plain", "image", "question-reply", "user-shell"].contains(caseName)
        let line = fixtureLine("codex-rollout-modern.jsonl", tag: caseName)
        #expect(!line.isEmpty)
        switch parseCodexRolloutLine(line, header: modernSession) {
        case .record(let message):
            #expect(counted)
            #expect(message == OwnerMessage(
                agent: .codex,
                sessionId: "s-modern",
                timestamp: isoDate("2026-11-18T17:54:11.035Z"),
                cwd: "/Users/example/Documents/Projects/02_Products/orbit",
                source: .transcript
            ))
        case .skipped:
            #expect(!counted)
        case .malformed:
            Issue.record("Valid rollout fixture was reported malformed: \(caseName)")
        }
    }

    @Test func legacyUserRowWithoutTimestampIsNil() {
        let header = CodexSessionHeader(
            sessionId: "s-legacy",
            cwd: "/Users/example/Desktop/site-v4.0",
            isDelegated: false,
            startedAt: isoDate("2025-09-03T10:39:35.000Z")
        )
        let line = fixtureLine("codex-rollout-legacy.jsonl", tag: "plain")
        #expect(!line.isEmpty)
        if case .skipped = parseCodexRolloutLine(line, header: header) {
        } else {
            Issue.record("An untimed user row must be skipped without borrowing the session start time")
        }
    }

    @Test(arguments: [("plain", false), ("hc-relay", true)])
    func historyLine(caseName: String, isRelay: Bool) {
        let line = fixtureLine("codex-history.jsonl", tag: caseName)
        #expect(!line.isEmpty)
        switch parseCodexHistoryLine(line) {
        case .record(let entry):
            #expect(entry == CodexHistoryEntry(
                sessionId: "s1",
                timestamp: isoDate("2025-09-03T10:40:26Z"),
                isRelay: isRelay
            ))
        case .skipped, .malformed:
            Issue.record("A valid history entry must be returned with its relay flag")
        }
    }

    @Test func malformedIsDistinctFromSkipped() {
        if case .malformed = parseCodexRolloutLine(Data("{".utf8), header: modernSession) {
        } else {
            Issue.record("Invalid rollout JSON must produce .malformed")
        }
        if case .malformed = parseCodexHistoryLine(Data("{".utf8)) {
        } else {
            Issue.record("Invalid history JSON must produce .malformed")
        }
        let line = fixtureLine("codex-rollout-modern.jsonl", tag: "assistant")
        #expect(!line.isEmpty)
        if case .skipped = parseCodexRolloutLine(line, header: modernSession) {
        } else {
            Issue.record("A valid assistant message must produce .skipped")
        }
    }

    @Test func rolloutPreservesUnknownCwd() {
        let header = CodexSessionHeader(
            sessionId: "s-modern", cwd: nil, isDelegated: false,
            startedAt: isoDate("2026-11-18T17:53:11.035Z")
        )
        switch parseCodexRolloutLine(fixtureLine("codex-rollout-modern.jsonl", tag: "plain"), header: header) {
        case .record(let message):
            #expect(message.agent == .codex)
            #expect(message.sessionId == "s-modern")
            #expect(message.timestamp == isoDate("2026-11-18T17:54:11.035Z"))
            #expect(message.cwd == nil)
            #expect(message.source == .transcript)
        case .skipped, .malformed:
            Issue.record("A usable message timestamp must survive an unknown working directory")
        }
    }
}
