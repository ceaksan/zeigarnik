import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct ScanConfigTests {
    let home = URL(fileURLWithPath: "/Users/example")

    @Test func standardConfigUsesHomeToolFoldersAndFirstRootTable() {
        let config = ScanConfig.standard(roots: [URL(fileURLWithPath: "/w/Code"), URL(fileURLWithPath: "/w/Other")], vaultRoot: nil, home: home)
        #expect(config.roots.map(\.path) == ["/w/Code", "/w/Other"])
        #expect(config.projectTableFile.path == "/w/Code/CLAUDE.md")
        #expect(config.claudeHome.path == "/Users/example/.claude")
        #expect(config.codexHome.path == "/Users/example/.codex")
        #expect(config.hcPath == "/Users/example/.local/bin/hc")
        #expect(config.vaultRoot.path == "/Users/example/.zeigarnik-no-vault")
        #expect(config.home == "/Users/example")
    }

    @Test func standardConfigWithoutRootsAndWithVault() {
        let config = ScanConfig.standard(roots: [], vaultRoot: URL(fileURLWithPath: "/v"), home: home)
        #expect(config.roots.isEmpty)
        #expect(config.projectTableFile.path == "/Users/example/.zeigarnik-no-table/CLAUDE.md")
        #expect(config.vaultRoot.path == "/v")
    }
}
