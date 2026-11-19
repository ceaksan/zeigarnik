import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct NoteDraftTests {
    let store: Store
    let project: String
    let now = Date(timeIntervalSince1970: 1_763_500_000)

    init() throws {
        store = try Store.inMemory()
        project = try store.upsertProject(resolution: .new, path: "/root/02_Products/orbit", displayName: "orbit", identity: nil)
    }

    func row(state: ProjectState = .active, readme: ReadmeDrift? = .current, architecture: ArchitectureDoc? = ArchitectureDoc.none,
             status: GitStatus? = GitStatus(branch: "main", upstream: "origin/main", ahead: 0, behind: 0, changed: 0, untracked: 0, stash: 0)) -> ProjectRow {
        ProjectRow(id: project, displayName: "orbit", summary: nil, path: "/root/02_Products/orbit", state: state, pinned: false,
                   lastActivityAt: nil, lastActivityAgent: nil, lastCommitAt: nil, status: status, lastFetchAt: nil,
                   readme: readme, spec: nil, activeTasksOpen: nil, error: nil, totalSeconds: 0, architecture: architecture)
    }

    @Test func cleanProjectHasNoDrafts() {
        #expect(noteDrafts(for: row()).isEmpty)
    }

    @Test func eachColumnStateGivesOneDraft() {
        let drafts = noteDrafts(for: row(
            readme: .behind(commits: 6, codeFiles: 4, manifestChanged: true),
            architecture: .behind(path: "architecture.md", updatedAt: nil, commitsSince: 9, newDirectories: ["Sources/Agent"], newFiles: 5, manifestChanged: false),
            status: GitStatus(branch: "main", upstream: "origin/main", ahead: 2, behind: 1, changed: 3, untracked: 1, stash: 0)))
        #expect(drafts.map(\.kind) == [.readme, .architecture, .push, .uncommitted])
        #expect(drafts.map(\.text) == [
            "Update the README: 6 commits behind, a manifest changed.",
            "Update architecture.md: 1 new folder, 5 new files.",
            "Sync main: 2 commits to push, 1 to pull.",
            "Commit or discard 4 changed files (3 modified, 1 untracked).",
        ])
        #expect(Set(drafts.map(\.fingerprint)).count == 4)
    }

    @Test func branchWithoutUpstreamGivesAPushDraft() {
        let drafts = noteDrafts(for: row(status: GitStatus(branch: "work", upstream: nil, ahead: nil, behind: nil, changed: 0, untracked: 0, stash: 0)))
        #expect(drafts.map(\.text) == ["Branch work has no upstream; push it or set one."])
    }

    @Test func missingProjectsAndDisabledChecksGiveNone() {
        let behind = ReadmeDrift.behind(commits: 6, codeFiles: 4, manifestChanged: false)
        #expect(noteDrafts(for: row(state: .missing, readme: behind)).isEmpty)
        #expect(noteDrafts(for: row(readme: behind), checks: NoteDraftChecks(readme: false, architecture: true)).isEmpty)
    }

    @Test func dismissedDraftStaysHiddenUntilItsStateChanges() throws {
        let six = noteDrafts(for: row(readme: .behind(commits: 6, codeFiles: 4, manifestChanged: false)))
        try store.dismissNoteDraft(six[0], now: now)
        #expect(try store.openNoteDrafts(six, projectIds: [project]).isEmpty)

        let nine = noteDrafts(for: row(readme: .behind(commits: 9, codeFiles: 4, manifestChanged: false)))
        #expect(try store.openNoteDrafts(nine, projectIds: [project]) == nine)
    }

    @Test func aClearedStateForgetsItsDismissal() throws {
        let six = noteDrafts(for: row(readme: .behind(commits: 6, codeFiles: 4, manifestChanged: false)))
        try store.dismissNoteDraft(six[0], now: now)
        #expect(try store.openNoteDrafts([], projectIds: [project]).isEmpty)
        #expect(try store.openNoteDrafts(six, projectIds: [project]) == six)
    }

    @Test func dismissalsOfProjectsNotInTheCallAreKept() throws {
        let six = noteDrafts(for: row(readme: .behind(commits: 6, codeFiles: 4, manifestChanged: false)))
        try store.dismissNoteDraft(six[0], now: now)
        _ = try store.openNoteDrafts([], projectIds: ["another"])
        #expect(try store.openNoteDrafts(six, projectIds: [project]).isEmpty)
    }

    @Test func acceptingADraftAddsTheEditedNoteAndHidesTheDraft() throws {
        let drafts = noteDrafts(for: row(status: GitStatus(branch: "main", upstream: "origin/main", ahead: 2, behind: 0, changed: 0, untracked: 0, stash: 0)))
        let note = try store.acceptNoteDraft(drafts[0], text: " Push after the review ", day: "2026-11-19", now: now)
        #expect(note.text == "Push after the review")
        #expect(try store.notes(projectId: project).map(\.text) == ["Push after the review"])
        #expect(try store.openNoteDrafts(drafts, projectIds: [project]).isEmpty)
        #expect(throws: OwnerDataError.emptyText) { try store.acceptNoteDraft(drafts[0], text: " ", day: "2026-11-19", now: now) }
    }
}
