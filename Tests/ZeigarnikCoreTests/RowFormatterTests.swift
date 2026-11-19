import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("RowFormatter")
struct RowFormatterTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Etc/GMT-3")!
        return value
    }

    private func row(
        name: String = "Alpha", state: ProjectState = .active, pinned: Bool = false,
        activity: Date? = nil, agent: Agent? = nil, commit: Date? = nil,
        status: GitStatus? = nil, readme: ReadmeDrift? = nil,
        spec: SpecHeadline? = nil, seconds: TimeInterval = 0
    ) -> ProjectRow {
        ProjectRow(
            id: name, displayName: name, summary: nil, path: "/synthetic/" + name,
            state: state, pinned: pinned, lastActivityAt: activity, lastActivityAgent: agent,
            lastCommitAt: commit, status: status, lastFetchAt: nil, readme: readme,
            spec: spec, activeTasksOpen: nil, error: nil, totalSeconds: seconds
        )
    }

    private func status(
        upstream: String? = "origin/main", ahead: Int? = 0, behind: Int? = 0,
        changed: Int = 0, untracked: Int = 0
    ) -> GitStatus {
        GitStatus(branch: "main", upstream: upstream, ahead: ahead, behind: behind,
                  changed: changed, untracked: untracked, stash: 8)
    }

    private func summary(_ stage: SpecStage, title: String = "Core scanner") -> SpecSummary {
        SpecSummary(specPath: "docs/specs/core.md", planPath: nil, date: nil,
                    title: title, declared: nil, stage: stage, evidence: nil)
    }

    private func current(_ stage: SpecStage, title: String = "Core scanner") -> SpecHeadline {
        SpecHeadline(current: summary(stage, title: title), lastDone: nil)
    }

    private func cell(_ column: Int, in row: ProjectRow) throws -> String {
        let output = formatProjectTable([row], errors: [], calendar: calendar)
        let lines = output.components(separatedBy: "\n")
        try #require(lines.count == 2)
        let cells = lines[1].components(separatedBy: "  ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try #require(cells.count == 8)
        return cells[column]
    }

    @Test func headerIsPresentWithoutProjects() {
        #expect(formatProjectTable([], errors: [], calendar: calendar)
                == "Project  Last activity  Last commit  Dirty  Push  README  ≈ Time  Spec")
    }

    @Test func projectUsesDisplayName() throws {
        #expect(try cell(0, in: row(name: "Named project")) == "Named project")
    }

    @Test func pinnedProjectHasStarPrefix() throws {
        #expect(try cell(0, in: row(pinned: true)) == "★ Alpha")
    }

    @Test func missingProjectHasSuffix() throws {
        #expect(try cell(0, in: row(state: .missing)) == "Alpha (missing)")
    }

    @Test func pinnedMissingProjectKeepsBothMarkers() throws {
        #expect(try cell(0, in: row(state: .missing, pinned: true)) == "★ Alpha (missing)")
    }

    @Test(arguments: [Agent.claude, .codex])
    func activityIncludesLocalDayAndAgent(agent: Agent) throws {
        let project = row(activity: isoDate("2026-11-18T22:30:00Z"), agent: agent)
        #expect(try cell(1, in: project) == "2026-11-19 " + agent.rawValue)
    }

    @Test func absentActivityIsDash() throws {
        #expect(try cell(1, in: row()) == "-")
    }

    @Test func incompleteActivityIsDash() throws {
        #expect(try cell(1, in: row(activity: isoDate("2026-11-18T22:30:00Z"))) == "-")
        #expect(try cell(1, in: row(agent: .claude)) == "-")
    }

    @Test func commitUsesLocalDay() throws {
        #expect(try cell(2, in: row(commit: isoDate("2026-11-18T22:30:00Z"))) == "2026-11-19")
    }

    @Test func absentCommitIsDash() throws {
        #expect(try cell(2, in: row()) == "-")
    }

    @Test func dirtySumsChangedAndUntrackedWithoutStash() throws {
        #expect(try cell(3, in: row(status: status(changed: 3, untracked: 2))) == "5")
    }

    @Test func cleanRepositoryHasZeroDirtyFiles() throws {
        #expect(try cell(3, in: row(status: status())) == "0")
    }

    @Test func absentStatusHasNoGitLabel() throws {
        #expect(try cell(3, in: row()) == "no git")
    }

    @Test func absentStatusHasNoPushValue() throws {
        #expect(try cell(4, in: row()) == "-")
    }

    @Test func absentUpstreamIsExplicit() throws {
        #expect(try cell(4, in: row(status: status(upstream: nil))) == "no upstream")
    }

    @Test func pushShowsAheadAndBehind() throws {
        #expect(try cell(4, in: row(status: status(ahead: 3, behind: 2))) == "↑3 ↓2")
    }

    @Test func missingPushCountsDefaultIndependentlyToZero() throws {
        #expect(try cell(4, in: row(status: status(ahead: nil, behind: 2))) == "↑0 ↓2")
        #expect(try cell(4, in: row(status: status(ahead: 3, behind: nil))) == "↑3 ↓0")
        #expect(try cell(4, in: row(status: status(ahead: nil, behind: nil))) == "↑0 ↓0")
    }

    @Test func currentReadmeIsOK() throws {
        #expect(try cell(5, in: row(readme: .current)) == "ok")
    }

    @Test func missingReadmeIsNone() throws {
        #expect(try cell(5, in: row(readme: .noReadme)) == "none")
    }

    @Test func readmeBehindUsesCommitCount() throws {
        #expect(try cell(5, in: row(readme: .behind(commits: 4, codeFiles: 12, manifestChanged: false))) == "behind 4")
    }

    @Test func readmeBehindIncludesManifestMarker() throws {
        #expect(try cell(5, in: row(readme: .behind(commits: 1, codeFiles: 3, manifestChanged: true))) == "behind 1 (manifest)")
    }

    @Test func absentReadmeStatusIsDash() throws {
        #expect(try cell(5, in: row()) == "-")
    }

    @Test func timeRoundsHoursToOneDecimal() throws {
        #expect(try cell(6, in: row(seconds: 44_280)) == "≈12.3h")
        #expect(try cell(6, in: row(seconds: 3_600)) == "≈1.0h")
        #expect(try cell(6, in: row(seconds: 3_528)) == "≈1.0h")
    }

    @Test func zeroTimeIsDash() throws {
        #expect(try cell(6, in: row()) == "-")
    }

    @Test func designSpecIncludesTitle() throws {
        #expect(try cell(7, in: row(spec: current(.design))) == "Design: Core scanner")
    }

    @Test func inProgressSpecIncludesCounts() throws {
        #expect(try cell(7, in: row(spec: current(.inProgress(done: 2, total: 7, external: 0)))) == "2/7: Core scanner")
    }

    @Test func inProgressSpecIncludesExternalCount() throws {
        #expect(try cell(7, in: row(spec: current(.inProgress(done: 2, total: 7, external: 3)))) == "2/7 (3 ext): Core scanner")
    }

    @Test func declaredDonePreservesEvidenceCounts() throws {
        #expect(try cell(7, in: row(spec: current(.declaredDone(done: 2, total: 7)))) == "declared done 2/7: Core scanner")
    }

    @Test func doneSpecIncludesTitle() throws {
        #expect(try cell(7, in: row(spec: current(.done))) == "Done: Core scanner")
    }

    @Test func lastDoneIsUsedWithoutCurrentSpec() throws {
        let spec = SpecHeadline(current: nil, lastDone: summary(.done, title: "Earlier work"))
        #expect(try cell(7, in: row(spec: spec)) == "Done: Earlier work")
    }

    @Test func currentSpecTakesPrecedenceOverLastDone() throws {
        let spec = SpecHeadline(current: summary(.design), lastDone: summary(.done, title: "Earlier work"))
        #expect(try cell(7, in: row(spec: spec)) == "Design: Core scanner")
    }

    @Test func absentSpecIsDash() throws {
        #expect(try cell(7, in: row()) == "-")
        #expect(try cell(7, in: row(spec: SpecHeadline(current: nil, lastDone: nil))) == "-")
    }

    @Test func longTitleKeepsFortyCharactersAndEllipsis() throws {
        let title = "1234567890123456789012345678901234567890extra"
        #expect(try cell(7, in: row(spec: current(.design, title: title)))
                == "Design: 1234567890123456789012345678901234567890…")
        let spec = SpecHeadline(current: nil, lastDone: summary(.done, title: title))
        #expect(try cell(7, in: row(spec: spec)) == "Done: 1234567890123456789012345678901234567890…")
    }

    @Test func exactlyFortyCharactersDoNotGainEllipsis() throws {
        let title = "1234567890123456789012345678901234567890"
        #expect(try cell(7, in: row(spec: current(.done, title: title)))
                == "Done: 1234567890123456789012345678901234567890")
    }

    @Test func titleTruncationCountsCharactersRatherThanUTF8Bytes() throws {
        let title = String(repeating: "ş", count: 41)
        #expect(try cell(7, in: row(spec: current(.design, title: title)))
                == "Design: " + String(repeating: "ş", count: 40) + "…")
    }

    @Test func widthsFitHeaderAndAllRowsAndPreserveOrder() {
        let rows = [row(name: "Long project"), row(name: "B")]
        let expected = [
            "Project       Last activity  Last commit  Dirty   Push  README  ≈ Time  Spec",
            "Long project  -              -            no git  -     -       -       -",
            "B             -              -            no git  -     -       -       -",
        ].joined(separator: "\n")
        #expect(formatProjectTable(rows, errors: [], calendar: calendar) == expected)
    }

    @Test func errorsFollowTableAfterBlankLine() {
        let errors = [ScanError(projectPath: "/synthetic/Alpha", message: "fetch failed"),
                      ScanError(projectPath: nil, message: "activity unavailable")]
        let expected = "Project  Last activity  Last commit  Dirty  Push  README  ≈ Time  Spec\n\nErrors:\n/synthetic/Alpha : fetch failed\n- : activity unavailable"
        #expect(formatProjectTable([], errors: errors, calendar: calendar) == expected)
    }

    @Test func errorsDoNotReplaceProjectRows() {
        let output = formatProjectTable([row()], errors: [ScanError(projectPath: nil, message: "failure")], calendar: calendar)
        #expect(output.components(separatedBy: "\n").count == 5)
        #expect(output.hasSuffix("\n\nErrors:\n- : failure"))
    }
}
