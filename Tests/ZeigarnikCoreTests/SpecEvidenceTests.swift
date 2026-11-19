import Foundation
import Testing
@testable import ZeigarnikCore

private func task(_ n: Int = 1, create: [String] = [], modify: [String] = [], test: [String] = [], checked: Int = 0, boxes: Int = 0, subject: String? = nil, external: Bool = false) -> PlanTask {
    PlanTask(number: n, title: "T\(n)", createPaths: create, modifyPaths: modify, testPaths: test, checked: checked, checkboxes: boxes, commitSubject: subject, isExternal: external)
}

private func commit(_ hash: String, _ files: [String], subject: String? = nil) -> CommitRecord {
    CommitRecord(hash: hash, parents: [], authorDate: Date(), subject: subject ?? hash, files: files)
}

private func context(tracked: Set<String>, history: [CommitRecord], introducedBy: String?) -> EvidenceContext {
    EvidenceContext(trackedFiles: tracked, history: history, planIntroducedBy: introducedBy, fileExists: { tracked.contains($0) })
}

private func evidence(done: Int, total: Int, external: Int) -> PlanEvidence {
    var details: [TaskEvidenceDetail] = []
    for i in 0..<total {
        let e: TaskEvidence = i < done ? .done : (i < done + external ? .external : .pending(missing: ["x"]))
        details.append(TaskEvidenceDetail(number: i + 1, title: "T", evidence: e, resolvedPaths: [], matchedCommits: []))
    }
    return PlanEvidence(tasks: details)
}

@Suite("SpecEvidence")
struct SpecEvidenceTests {
    @Test func modifyCountsThePlanIntroducingCommit() {
        let history = [commit("c2", ["docs/plans/p.md", "Sources/A.swift"]), commit("c1", ["Sources/A.swift"])]
        let detail = evaluate(task(modify: ["Sources/A.swift"]), in: context(tracked: ["Sources/A.swift"], history: history, introducedBy: "c2"))
        #expect(detail.evidence == .done)
        #expect(detail.matchedCommits == ["c2"])
    }

    @Test func modifyBeforePlanIsNotEvidence() {
        let history = [commit("c2", ["docs/plans/p.md"]), commit("c1", ["Sources/A.swift"])]
        #expect(evaluate(task(modify: ["Sources/A.swift"]), in: context(tracked: ["Sources/A.swift"], history: history, introducedBy: "c2")).evidence == .pending(missing: ["Sources/A.swift"]))
    }

    @Test func createNeedsFileToExist() {
        #expect(evaluate(task(create: ["x/B.swift"]), in: context(tracked: [], history: [], introducedBy: nil)).evidence == .pending(missing: ["x/B.swift"]))
    }

    @Test func globAndDirectoryResolveAgainstTrackedFiles() {
        let tracked: Set<String> = ["schema/v1/examples/ingredient.cup.json", "schema/v1/fixtures/a.json"]
        let detail = evaluate(task(create: ["schema/v1/examples/ingredient.*.json", "schema/v1/fixtures/"]), in: context(tracked: tracked, history: [], introducedBy: nil))
        #expect(detail.evidence == .done)
        #expect(detail.resolvedPaths.contains("schema/v1/examples/ingredient.cup.json"))
    }

    @Test func commitSubjectMatchesModifyButNotMissingCreate() {
        let history = [commit("p", ["docs/plans/p.md"]), commit("s", ["spike/cli.py"], subject: "feat: cli")]
        let ctx = context(tracked: ["spike/cli.py"], history: history, introducedBy: "p")
        let modifyOnly = evaluate(task(modify: ["spike/cli.py"], subject: "feat: cli"), in: ctx)
        #expect(modifyOnly.evidence == .done)
        #expect(modifyOnly.matchedCommits.contains("s"))
        let withMissingCreate = evaluate(task(create: ["spike/missing.py"], modify: ["spike/cli.py"], subject: "feat: cli"), in: ctx)
        #expect(withMissingCreate.evidence == .pending(missing: ["spike/missing.py"]))
    }

    @Test func externalTaskStaysPending() {
        #expect(evaluate(task(create: ["a.js"], external: true), in: context(tracked: ["a.js"], history: [], introducedBy: nil)).evidence == .external)
    }

    @Test func checkboxFallbackAndNoEvidence() {
        let ctx = context(tracked: [], history: [], introducedBy: nil)
        #expect(evaluate(task(checked: 2, boxes: 2), in: ctx).evidence == .done)
        #expect(evaluate(task(checked: 1, boxes: 2), in: ctx).evidence == .pending(missing: []))
        #expect(evaluate(task(), in: ctx).evidence == .noEvidence)
    }

    @Test func planEvidenceExcludesNoEvidenceFromDenominator() {
        let details = [
            TaskEvidenceDetail(number: 1, title: "a", evidence: .done, resolvedPaths: [], matchedCommits: []),
            TaskEvidenceDetail(number: 2, title: "b", evidence: .noEvidence, resolvedPaths: [], matchedCommits: []),
            TaskEvidenceDetail(number: 3, title: "c", evidence: .external, resolvedPaths: [], matchedCommits: []),
        ]
        let e = PlanEvidence(tasks: details)
        #expect(e.done == 1)
        #expect(e.denominator == 2)
        #expect(e.external == 1)
    }

    @Test func approvedSpecWithFullEvidenceIsDone() {
        #expect(specStage(declared: "Approved by user", plan: evidence(done: 7, total: 7, external: 0), override: nil) == .done)
    }

    @Test func acceptedSpecWithExternalTaskIsNotDone() {
        #expect(specStage(declared: "Accepted, implemented 2026-10-15", plan: evidence(done: 10, total: 11, external: 1), override: nil) == .inProgress(done: 10, total: 11, external: 1))
    }

    @Test func declaredCompletionAloneIsDeclaredDone() {
        #expect(specStage(declared: "Implemented", plan: evidence(done: 3, total: 5, external: 0), override: nil) == .declaredDone(done: 3, total: 5))
    }

    @Test func ownerOverrideWins() {
        #expect(specStage(declared: nil, plan: evidence(done: 7, total: 7, external: 0), override: .notDone) == .inProgress(done: 7, total: 7, external: 0))
        #expect(specStage(declared: nil, plan: evidence(done: 1, total: 7, external: 0), override: .done) == .done)
    }

    @Test func specWithoutPlanIsDesign() {
        #expect(specStage(declared: nil, plan: nil, override: nil) == .design)
    }

    @Test func C1_planWithoutEvidenceHasNoFraction() {
        let empty = PlanEvidence(tasks: [TaskEvidenceDetail(number: 1, title: "Discuss orbit", evidence: .noEvidence, resolvedPaths: [], matchedCommits: [])])
        #expect(specStage(declared: nil, plan: empty, override: nil) == .design)
        #expect(specStage(declared: "Implemented", plan: empty, override: nil) == .design)
        #expect(specStage(declared: nil, plan: empty, override: .notDone) == .design)
        #expect(specStage(declared: nil, plan: empty, override: .done) == .done)
    }
}

@Suite("SpecCatalog")
struct SpecCatalogTests {
    private func write(_ repo: URL, _ path: String, _ text: String) throws {
        let url = repo.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func twoPlanSummary(existingFiles: Set<String>) throws -> SpecSummary {
        let repo = try makeTempDir()
        let specPath = "docs/superpowers/specs/2026-01-01-x-design.md"
        let appPlan = "docs/superpowers/plans/2026-01-01-x-app.md"
        let corePlan = "docs/superpowers/plans/2026-01-01-x-core.md"
        try write(repo, specPath, "# X design\n")
        try write(repo, appPlan, """
        # X app plan
        **Spec:** `\(specPath)`

        ### Task 1: First app file
        - Create: `src/app-a.swift`

        ### Task 2: Second app file
        - Create: `src/app-b.swift`
        """)
        try write(repo, corePlan, """
        # X core plan
        **Spec:** `\(specPath)`

        ### Task 1: First core file
        - Create: `src/core-a.swift`

        ### Task 2: Second core file
        - Create: `src/core-b.swift`
        """)
        for path in existingFiles { try write(repo, path, "Synthetic file.\n") }
        let ctx = EvidenceContext(
            trackedFiles: existingFiles, history: [], planIntroducedBy: nil,
            fileExists: { FileManager.default.fileExists(atPath: repo.appendingPathComponent($0).path) }
        )
        let summaries = try catalogSpecs(repo: repo, context: ctx, overrides: [:])
        #expect(summaries.count == 1)
        return try #require(summaries.first { $0.specPath == specPath })
    }

    @Test func specWithTwoPlansCombinesEvidence() throws {
        let summary = try twoPlanSummary(existingFiles: ["src/core-a.swift", "src/core-b.swift"])
        #expect(summary.stage == .inProgress(done: 2, total: 4, external: 0))
        #expect(summary.planPaths == [
            "docs/superpowers/plans/2026-01-01-x-app.md",
            "docs/superpowers/plans/2026-01-01-x-core.md",
        ])
        #expect(summary.planPath == "docs/superpowers/plans/2026-01-01-x-core.md")
        #expect(summary.evidence?.tasks.count == 4)
    }

    @Test func specWithTwoPlansIsNotDoneUntilBothAre() throws {
        let summary = try twoPlanSummary(existingFiles: ["src/app-a.swift", "src/core-a.swift", "src/core-b.swift"])
        #expect(summary.stage == .inProgress(done: 3, total: 4, external: 0))
        #expect(summary.stage != .done)
        if case .declaredDone = summary.stage {
            Issue.record("A spec without a completion declaration must not be declared done while an app file is missing")
        }
    }

    @Test func oldSpecSummaryJSONWithoutPlanPathsDecodes() throws {
        let json = #"{"specPath":"docs/specs/old.md","planPath":"docs/plans/old.md","date":"2026-01-01","title":"Legacy summary","declared":null,"stage":{"design":{}},"evidence":null}"#
        let summary = try JSONDecoder().decode(SpecSummary.self, from: Data(json.utf8))
        #expect(summary.planPath == "docs/plans/old.md")
        #expect(summary.planPaths == ["docs/plans/old.md"])
        #expect(summary.stage == .design)
    }

    @Test func catalogLinksByPrimarySpecThenBySlug() async throws {
        let repo = try await makeRepo()
        try write(repo, "docs/superpowers/specs/2026-11-07-x-design.md", "# X design\n\n**Status:** Approved\n")
        try write(repo, "docs/superpowers/plans/2026-11-07-x.md", "# X plan\n\n### Task 1: A\n\n- Create: `src/a.swift`\n")
        try write(repo, "docs/superpowers/specs/2026-11-08-y-design.md", "# Y design\n")
        try write(repo, "docs/superpowers/plans/2026-11-09-other.md", "# Other plan\n\n**Spec:** `docs/superpowers/specs/2026-11-08-y-design.md`\n\n### Task 1: B\n\n- Create: `src/b.swift`\n")
        try write(repo, "src/a.swift", "x")
        await runGit(repo, ["add", "-A"])
        await runGit(repo, ["commit", "-q", "-m", "specs"])
        let inspector = GitInspector(runner: ProcessRunner())
        let tracked = try await inspector.trackedFiles(repo)
        let ctx = EvidenceContext(trackedFiles: tracked, history: try await inspector.history(repo), planIntroducedBy: nil,
                                  fileExists: { FileManager.default.fileExists(atPath: repo.appendingPathComponent($0).path) })
        let specs = try catalogSpecs(repo: repo, context: ctx, overrides: [:])
        let x = try #require(specs.first { $0.specPath == "docs/superpowers/specs/2026-11-07-x-design.md" })
        #expect(x.planPath == "docs/superpowers/plans/2026-11-07-x.md")
        #expect(x.stage == .done)
        #expect(x.title == "X design")
        #expect(x.date == "2026-11-07")
        let y = try #require(specs.first { $0.specPath == "docs/superpowers/specs/2026-11-08-y-design.md" })
        #expect(y.planPath == "docs/superpowers/plans/2026-11-09-other.md")
        #expect(y.stage == .inProgress(done: 0, total: 1, external: 0))
    }

    @Test func openSpecActiveAndArchived() async throws {
        let repo = try await makeRepo()
        try write(repo, "openspec/changes/add-x/tasks.md", "- [x] a\n- [ ] b\n")
        try write(repo, "openspec/changes/archive/2026-01-01-old/tasks.md", "- [x] a\n")
        let ctx = EvidenceContext(trackedFiles: [], history: [], planIntroducedBy: nil, fileExists: { _ in false })
        let specs = try catalogSpecs(repo: repo, context: ctx, overrides: [:])
        #expect(specs.first { $0.specPath == "openspec/changes/add-x" }?.stage == .inProgress(done: 1, total: 2, external: 0))
        #expect(specs.first { $0.specPath == "openspec/changes/archive/2026-01-01-old" }?.stage == .done)
    }

    @Test func C2_openSpecWithoutTasksHasNoFraction() throws {
        let repo = try makeTempDir()
        try write(repo, "openspec/changes/orbit/proposal.md", "# Orbit\n")
        try write(repo, "openspec/changes/lumen/tasks.md", "# Lumen\nNo tasks yet.\n")
        let ctx = EvidenceContext(trackedFiles: [], history: [], planIntroducedBy: nil, fileExists: { _ in false })
        let specs = try catalogSpecs(repo: repo, context: ctx, overrides: [:])
        #expect(specs.count == 2)
        #expect(specs.allSatisfy { $0.stage == .design })
    }

    @Test func headlinePicksNewestNotDone() {
        func s(_ path: String, _ date: String, _ stage: SpecStage) -> SpecSummary {
            SpecSummary(specPath: path, planPath: nil, date: date, title: path, declared: nil, stage: stage, evidence: nil)
        }
        let a = s("a", "2026-01-01", .done), b = s("b", "2026-02-01", .inProgress(done: 1, total: 2, external: 0)), c = s("c", "2026-03-01", .done)
        #expect(headline([a, b, c]) == SpecHeadline(current: b, lastDone: c))
        #expect(headline([a, c]) == SpecHeadline(current: nil, lastDone: c))
    }
}

@Suite("ActiveTasks")
struct ActiveTasksTests {
    @Test func activeTasksCountsOpenBoxesOutsideFences() {
        #expect(openCheckboxCount("- [ ] a\n- [ ] b\n- [x] c\n  - [ ] nested\n- [X] d\n```\n- [ ] fenced\n```\n") == 3)
    }

    @Test func activeTasksURLDoesNotDuplicatePrefix() {
        #expect(activeTasksURL(vaultRoot: URL(fileURLWithPath: "/v"), vaultDirectory: "03_Active_Projects/02_Public/lumen/").path == "/v/03_Active_Projects/02_Public/lumen/tasks/Active Tasks.md")
    }
}
