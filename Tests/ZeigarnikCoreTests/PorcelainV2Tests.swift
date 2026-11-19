import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("PorcelainV2")
struct PorcelainV2Tests {
    private func z(_ entries: [String]) -> Data { Data((entries.joined(separator: "\0") + "\0").utf8) }

    private let sample: [String] = [
        "# branch.oid 1111111111111111111111111111111111111111",
        "# branch.head main",
        "# branch.upstream origin/main",
        "# branch.ab +2 -1",
        "# stash 3",
        "1 .M N... 100644 100644 100644 aaa bbb Sources/A.swift",
        "2 R. N... 100644 100644 100644 aaa bbb R100 new name.swift", "old name.swift",
        "u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt",
        "? u/one.txt", "? u/two.txt", "? u/three.txt",
        "! ignored.log",
    ]

    @Test func parsesHeadersAndCounts() {
        #expect(parsePorcelainV2(z(sample)) == GitStatus(branch: "main", upstream: "origin/main", ahead: 2, behind: 1, changed: 3, untracked: 3, stash: 3))
    }

    @Test func detachedAndNoUpstream() {
        let status = parsePorcelainV2(z(["# branch.oid 1111111111111111111111111111111111111111", "# branch.head (detached)"]))
        #expect(status == GitStatus(branch: nil, upstream: nil, ahead: nil, behind: nil, changed: 0, untracked: 0, stash: 0))
    }

    @Test func parsesThreeThousandUntrackedEntries() {
        let entries = ["# branch.head main"] + (0..<3_000).map { "? dir/f\($0).txt" }
        let start = Date()
        #expect(parsePorcelainV2(z(entries)).untracked == 3_000)
        #expect(Date().timeIntervalSince(start) < 0.5)
    }

    @Test func sanitizesCredentials() {
        #expect(sanitizeRemoteURL("https://user:tok@gitlab.com/a/b.git") == "https://gitlab.com/a/b.git")
        #expect(sanitizeRemoteURL("https://tok@github.com/a/b") == "https://github.com/a/b")
        #expect(sanitizeRemoteURL("git@github.com:a/b.git") == "git@github.com:a/b.git")
        #expect(sanitizeRemoteURL("ssh://git@host.example/a.git") == "ssh://host.example/a.git")
    }

    @Test func parsesWorktreeList() {
        let output = "worktree /r/main\nHEAD abc\nbranch refs/heads/main\n\nworktree /r/main/.wt/x\nHEAD def\ndetached\n"
        #expect(parseWorktreeList(output).map(\.path) == ["/r/main", "/r/main/.wt/x"])
    }

    @Test func aggregateSumsDirtyAcrossCheckouts() {
        let main = GitStatus(branch: "main", upstream: "origin/main", ahead: 1, behind: 0, changed: 1, untracked: 0, stash: 2)
        let other = GitStatus(branch: "feat", upstream: nil, ahead: nil, behind: nil, changed: 2, untracked: 3, stash: 0)
        #expect(aggregateStatus(main: main, others: [other]) == GitStatus(branch: "main", upstream: "origin/main", ahead: 1, behind: 0, changed: 3, untracked: 3, stash: 2))
    }
}
