import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("PlanParser")
struct PlanParserTests {
    @Test func ignoresParentheticalBackticks() throws {
        let plan = parsePlan(fixture("plan-board-task1.md"))
        let t = try #require(plan.tasks.first)
        #expect(t.number == 1)
        #expect(t.testPaths == ["PlannerKitTests/ModelsTests.swift"])
        #expect(t.modifyPaths == ["PlannerKit/Models/Bed.swift", "PlannerKit/Storage/FileFormat.swift", "PlannerKit/Storage/Paths.swift"])
        #expect(t.createPaths == ["PlannerKit/Models/Planting.swift", "docs/adr/ADR-001-plantings-per-bed.md"])
        #expect(!t.isExternal)
    }

    @Test func resolvesGroupedSiblingsAndGlobs() throws {
        let t = try #require(parsePlan(fixture("plan-sample-task1.md")).tasks.first)
        #expect(t.createPaths.contains("schema/v1/ingredient.schema.json"))
        #expect(t.createPaths.contains("schema/v1/examples/ingredient.*.json"))
        #expect(t.createPaths.contains("schema/check_schema.py"))
        #expect(!t.createPaths.contains("ingredient.schema.json"))
    }

    @Test func readsCommitSubject() throws {
        let t = try #require(parsePlan(fixture("plan-sample-task5.md")).tasks.first)
        #expect(t.number == 5)
        #expect(t.commitSubject == "feat(cli): recipe CLI (list, show) and schema test")
        #expect(!t.isExternal)
    }

    @Test func primarySpecWinsOverParent() {
        #expect(parsePlan(fixture("plan-sample-task1.md")).primarySpec == "docs/superpowers/specs/2026-01-10-recipe-box-design.md")
    }

    @Test func externalOnlyFromTitleOrExplicitMarker() {
        #expect(!(parsePlan(fixture("plan-hosted-task8.md")).tasks.first?.isExternal ?? true))
        let md = """
        # P

        ### Task 1: Release (orchestrator only)

        - [ ] **Step 1:** tag and publish

        ### Task 2: Wire the client

        **External:** verify in the staging Preview

        - Create: `a.js`

        ### Task 3: Opening and Preview screens

        - Create: `ui/preview.tsx`
        """
        #expect(parsePlan(md).tasks.map(\.isExternal) == [true, true, false])
    }

    @Test func countsCheckboxesOutsideFences() throws {
        let md = "# P\n\n### Task 1: A\n\n- [x] one\n- [ ] two\n```\n- [ ] fenced\n```\n"
        let t = try #require(parsePlan(md).tasks.first)
        #expect(t.checked == 1)
        #expect(t.checkboxes == 2)
    }

    @Test func statusOnlyFromHeaderNotFencedBody() {
        #expect(declaredStatus(fixture("plan-fenced-status.md")) == nil)
        #expect(declaredStatus("# T\n\n```\n**Status:** Accepted\n```\n\n## A\n") == nil)
        #expect(declaredStatus(fixture("spec-board-header.md")) == "Approved 2026-01-07; the season boundary items were confirmed 2026-01-08.")
        #expect(declaredStatus("---\ntitle: x\nstatus: done\n---\n# T\n") == "done")
    }

    @Test func classifiesStatusByFirstWord() {
        #expect(classifyStatus("Approved 2026-01-07") == .approval)
        #expect(classifyStatus("Accepted, implemented 2026-10-15") == .approval)
        #expect(classifyStatus("Implemented") == .completion)
        #expect(classifyStatus("done") == .completion)
        #expect(classifyStatus("Exploring options") == .other)
        #expect(classifyStatus(nil) == .none)
    }
}
