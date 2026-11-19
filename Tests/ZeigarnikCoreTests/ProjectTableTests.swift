import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("ProjectTable")
struct ProjectTableTests {
    @Test func parsesProjectTable() {
        let rows = parseProjectTable(fixture("project-table.md"))
        #expect(rows.count == 6)
        #expect(rows.first { $0.name == "Lumen" }?.directory == "lumen")
        #expect(rows.first { $0.name == "Lumen" }?.vaultDirectory == "03_Active_Projects/02_Public/lumen/")
        #expect(rows.first { $0.name == "Harbor" }?.directory == "../Side_Projects/harbor")
        #expect(rows.first { $0.name == "Weather Station" }?.directory == nil)
        #expect(rows.first { $0.name == "Garden Planner" }?.vaultDirectory == nil)
    }

    @Test func ignoresOtherTables() {
        #expect(!parseProjectTable(fixture("project-table.md")).contains { $0.name == "x" })
    }
}
