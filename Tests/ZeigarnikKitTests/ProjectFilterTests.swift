import Foundation
import Testing
@testable import ZeigarnikKit

func row(_ id: String, path: String? = nil, state: ProjectState = .active, pinned: Bool = false, activity: Date? = nil,
         commit: Date? = nil, status: GitStatus? = nil, readme: ReadmeDrift? = nil, seconds: TimeInterval = 0, architecture: ArchitectureDoc? = nil,
         visibility: RepoVisibility? = nil) -> ProjectRow {
    ProjectRow(id: id, displayName: id, summary: nil, path: path ?? "/r/02_Products/\(id)", state: state, pinned: pinned,
               lastActivityAt: activity, lastActivityAgent: nil, lastCommitAt: commit, status: status, lastFetchAt: nil,
               readme: readme, spec: nil, activeTasksOpen: nil, error: nil, totalSeconds: seconds, architecture: architecture,
               visibility: visibility)
}

func status(branch: String? = "main", upstream: String? = "origin/main", ahead: Int? = 0, behind: Int? = 0, changed: Int = 0, untracked: Int = 0) -> GitStatus {
    GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, changed: changed, untracked: untracked, stash: 0)
}

@Suite struct ProjectFilterTests {
    let now = Date(timeIntervalSince1970: 1_763_550_000)
    var ctx: FilterContext { FilterContext(now: now, openNow: .known([.project("b")]), roots: ["/r"]) }

    @Test func missingProjectOnlyInMissingAndPinned() {
        let gone = row("a", state: .missing, pinned: true)
        #expect(matches(gone, .missing, ctx))
        #expect(matches(gone, .pinned, ctx))
        #expect(!matches(gone, .all, ctx))
        #expect(!matches(gone, .folder("02_Products"), ctx))
        #expect(!matches(row("a"), .missing, ctx))
    }

    @Test func unknownStatusIsNotUncommitted() {
        #expect(!matches(row("a"), .uncommitted, ctx))
        #expect(matches(row("a", status: status(untracked: 1)), .uncommitted, ctx))
        #expect(Format.dirty(nil) == "?")
        #expect(Format.dirty(status(changed: 2, untracked: 1)) == "3")
    }

    @Test func pushRules() {
        #expect(matches(row("a", status: status(upstream: nil, ahead: nil, behind: nil)), .pushOrUpstream, ctx))
        #expect(matches(row("a", status: status(ahead: 2)), .pushOrUpstream, ctx))
        #expect(matches(row("a", status: status(behind: 1)), .pushOrUpstream, ctx))
        #expect(!matches(row("a", status: status()), .pushOrUpstream, ctx))
        #expect(!matches(row("a"), .pushOrUpstream, ctx))
    }

    @Test func readmeAndQuietRules() {
        #expect(matches(row("a", readme: .behind(commits: 3, codeFiles: 2, manifestChanged: false)), .readmeDrift, ctx))
        #expect(!matches(row("a", readme: .current), .readmeDrift, ctx))
        #expect(matches(row("a"), .quiet, ctx))
        #expect(matches(row("a", activity: now.addingTimeInterval(-31 * 86400)), .quiet, ctx))
        #expect(!matches(row("a", activity: now.addingTimeInterval(-31 * 86400), commit: now.addingTimeInterval(-86400)), .quiet, ctx))
    }

    @Test func openNowCountAbsentWhenUnknown() {
        let rows = [row("a"), row("b")]
        #expect(filterCounts(rows, ctx)[.openNow] == 1)
        let unknown = FilterContext(now: now, openNow: .unknown("x"), roots: ["/r"])
        #expect(filterCounts(rows, unknown)[.openNow] == nil)
        #expect(filterCounts(rows, unknown)[.all] == 2)
        #expect(filterCounts(rows, unknown)[.folder("02_Products")] == 2)
    }

    @Test func folderOfRootLevelRepoIsRoot() {
        #expect(folder(of: row("lumen", path: "/r/lumen"), roots: ["/r"]) == "Root")
        #expect(folder(of: row("orbit", path: "/r/02_Products/orbit"), roots: ["/r/"]) == "02_Products")
        #expect(folder(of: row("harbor", path: "/x/harbor"), roots: ["/r"]) == "Outside")
    }

    @Test func anyFirstLevelFolderGroupsItsProjectsWithoutANumberPrefix() {
        #expect(folder(of: row("orbit", path: "/r/Work/orbit"), roots: ["/r"]) == "Work")
        #expect(folder(of: row("lumen", path: "/r/side projects/web/lumen"), roots: ["/r"]) == "side projects")
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        let rows = [row("Türkçe Yemek Tarifleri"), row("orbit")]
        #expect(search(rows, "turkce").map(\.id) == ["Türkçe Yemek Tarifleri"])
        #expect(search(rows, "  ").count == 2)
        #expect(search(rows, "02_products/orb").map(\.id) == ["orbit"])
    }

    @Test func searchMatchesDottedAndDotlessIBothWays() {
        let rows = [row("Northwind Inspector"), row("CI Status Board"), row("İzmir Rehberi"), row("Işık Atlası")]
        #expect(search(rows, "inspect").map(\.id) == ["Northwind Inspector"])
        #expect(search(rows, "ci s").map(\.id) == ["CI Status Board"])
        #expect(search(rows, "izmir").map(\.id) == ["İzmir Rehberi"])
        #expect(search(rows, "isik").map(\.id) == ["Işık Atlası"])
        #expect(search(rows, "IŞIK").map(\.id) == ["Işık Atlası"])
    }

    @Test func sortPutsNilLastBothWays() {
        let rows = [row("a", activity: nil), row("b", activity: now), row("c", activity: now.addingTimeInterval(-60))]
        #expect(sorted(rows, by: .lastActivity, ascending: true).map(\.id) == ["c", "b", "a"])
        #expect(sorted(rows, by: .lastActivity, ascending: false).map(\.id) == ["b", "c", "a"])
        let dirty = [row("x", status: status(changed: 5)), row("y"), row("z", status: status(changed: 9))]
        #expect(sorted(dirty, by: .dirty, ascending: false).map(\.id) == ["z", "x", "y"])
    }

    @Test func stableColorIndexIsFixed() {
        #expect(stableColorIndex(for: "orbit") == 3)
        #expect(stableColorIndex(for: "lumen") == 2)
    }

    @Test func architectureFilterCountsOnlyBehindDocuments() {
        let ctx = FilterContext(now: Date(), openNow: nil, roots: ["/r"])
        let behind = ArchitectureDoc.behind(path: "architecture.md", updatedAt: nil, commitsSince: 9, newDirectories: ["src/x"], newFiles: 1, manifestChanged: false)
        let rows = [row("a", architecture: behind), row("b", architecture: .current(path: "architecture.md", updatedAt: nil, commitsSince: 0)),
                    row("c", architecture: ArchitectureDoc.none), row("d"), row("e", state: .missing, architecture: behind)]
        #expect(rows.filter { matches($0, .architectureDrift, ctx) }.map(\.id) == ["a"])
        #expect(filterCounts(rows, ctx)[.architectureDrift] == 1)
    }
}
