import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct SourceHealthTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("zg-src-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in ["root", "vault", ".claude/projects", ".codex/sessions"] {
            try fm.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in [".claude/history.jsonl", ".codex/history.jsonl"] {
            try Data().write(to: home.appendingPathComponent(file))
        }
    }

    func config(roots: [String] = ["root"]) -> ScanConfig {
        ScanConfig(roots: roots.map { home.appendingPathComponent($0) }, projectTableFile: home.appendingPathComponent("root/CLAUDE.md"),
                   vaultRoot: home.appendingPathComponent("vault"), claudeHome: home.appendingPathComponent(".claude"),
                   codexHome: home.appendingPathComponent(".codex"), hcPath: "/nonexistent/hc", home: home.path)
    }

    @Test func healthySetupHasNoProblems() {
        #expect(checkSources(config(), vaultConfigured: true).isEmpty)
    }

    @Test func missingAgentSourcesMeanTheToolIsNotUsed() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".codex"))
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude"))
        #expect(checkSources(config(), vaultConfigured: false).isEmpty)
        #expect(checkSources(config(roots: []), vaultConfigured: false).map(\.kind) == [.root])
    }

    @Test func unreadableAgentSourceIsNamed() throws {
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sessions.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sessions.path) }
        let problems = checkSources(config(), vaultConfigured: false)
        #expect(problems.map(\.kind) == [.codexSessions])
        #expect(problems.first?.reason == .unreadable)
        #expect(problems.first?.message.contains(sessions.path) == true)
    }

    @Test func vaultCheckedOnlyWhenConfigured() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent("vault"))
        #expect(checkSources(config(), vaultConfigured: false).isEmpty)
        #expect(checkSources(config(), vaultConfigured: true).map(\.kind) == [.vault])
    }

    @Test func unreadableRootIsUnreadable() throws {
        let root = home.appendingPathComponent("root")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let problems = checkSources(config(), vaultConfigured: true)
        #expect(problems.map(\.kind) == [.root])
        #expect(problems.first?.reason == .unreadable)
    }

    @Test func messagesNameTheSourceInEnglish() {
        #expect(SourceProblem(kind: .root, path: "", reason: .missing).message == "No folder selected to scan.")
        #expect(SourceProblem(kind: .codexSessions, path: "/h/.codex/sessions", reason: .missing).message == "Codex sessions not found: /h/.codex/sessions")
        #expect(SourceProblem(kind: .vault, path: "/v", reason: .unreadable).message == "Vault cannot be read: /v")
    }
}
