import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("History")
struct HistoryTests {
    @Test func parsesLogRecordsWithFilesAndMergeParents() throws {
        let output = "\u{1e}bbb\u{1f}aaa ccc\u{1f}2026-11-18T10:00:00+03:00\u{1f}Merge branch x\n\n\u{1e}aaa\u{1f}\u{1f}2026-11-17T09:00:00+03:00\u{1f}feat: first: with colon\n\nREADME.md\nSources/A.swift\n"
        let records = parseLog(output)
        try #require(records.count == 2)
        #expect(records[0] == CommitRecord(hash: "bbb", parents: ["aaa", "ccc"], authorDate: isoDate("2026-11-18T07:00:00Z"), subject: "Merge branch x", files: []))
        #expect(records[1] == CommitRecord(hash: "aaa", parents: [], authorDate: isoDate("2026-11-17T06:00:00Z"), subject: "feat: first: with colon", files: ["README.md", "Sources/A.swift"]))
    }

    @Test func historyFromRealRepoIsNewestFirst() async throws {
        let repo = try await makeRepo()
        try Data("x".utf8).write(to: repo.appendingPathComponent("a.swift"))
        await runGit(repo, ["add", "a.swift"])
        await runGit(repo, ["commit", "-q", "-m", "second"])
        let history = try await GitInspector(runner: ProcessRunner()).history(repo)
        try #require(history.map(\.subject) == ["second", "init"])
        #expect(history[0].files == ["a.swift"])
    }

    @Test func commitsPerDayUsesLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Etc/GMT-3")!
        let history = [
            CommitRecord(hash: "a", parents: [], authorDate: isoDate("2026-11-18T22:30:00Z"), subject: "late", files: []),
            CommitRecord(hash: "b", parents: [], authorDate: isoDate("2026-11-18T10:00:00Z"), subject: "day", files: []),
        ]
        #expect(commitsPerDay(history, calendar: calendar) == ["2026-11-19": 1, "2026-11-18": 1])
    }
}

@Suite("ReadmeDrift")
struct ReadmeDriftTests {
    private func commit(_ hash: String, _ files: [String]) -> CommitRecord {
        CommitRecord(hash: hash, parents: [], authorDate: Date(), subject: hash, files: files)
    }

    @Test func noReadme() {
        #expect(readmeDrift(history: [commit("a", ["x.swift"])], readmePath: nil) == .noReadme)
    }

    @Test func currentWhenOnlyDocsChanged() {
        let h = (1...5).map { commit("d\($0)", ["docs/x\($0).md"]) } + [commit("r", ["README.md"])]
        #expect(readmeDrift(history: h, readmePath: "README.md") == .current)
    }

    @Test func behindWhenCodeChangedEnoughCommits() {
        let h = [commit("c3", ["src/a.swift"]), commit("c2", ["notes.md"]), commit("c1", ["src/a.swift"]), commit("r", ["README.md"])]
        #expect(readmeDrift(history: h, readmePath: "README.md") == .behind(commits: 3, codeFiles: 1, manifestChanged: false))
    }

    @Test func behindOnSingleManifestChange() {
        let h = [commit("m", ["package.json"]), commit("r", ["README.md"])]
        #expect(readmeDrift(history: h, readmePath: "README.md") == .behind(commits: 1, codeFiles: 1, manifestChanged: true))
    }

    @Test func notBehindBelowThresholdWithoutManifest() {
        let h = [commit("c2", ["src/a.swift"]), commit("c1", ["src/b.swift"]), commit("r", ["README.md"])]
        #expect(readmeDrift(history: h, readmePath: "README.md") == .current)
    }

    @Test func neverCommittedReadmeCountsEverything() {
        let h = [commit("c3", ["a.swift"]), commit("c2", ["b.swift"]), commit("c1", ["c.swift"])]
        #expect(readmeDrift(history: h, readmePath: "README.md") == .behind(commits: 3, codeFiles: 3, manifestChanged: false))
    }

    @Test func findsReadmeCaseInsensitivelyAtRoot() {
        #expect(findReadme(in: ["docs/README.md", "readme.md", "a.swift"]) == "readme.md")
        #expect(findReadme(in: ["docs/README.md"]) == nil)
    }

    @Test func summarySkipsHeadingBadgesAndHtml() {
        let md = "# T\n[![b](x)](y)\n<p align=center>..</p>\n\nA floating board that shows [what agents](https://x) decided.\nSecond line.\n\nNext paragraph."
        #expect(readmeSummary(md) == "A floating board that shows what agents decided. Second line.")
    }

    @Test func summarySkipsFrontmatterAndFences() {
        let md = "---\ntitle: x\n---\n```\ncode line\n```\n> quote\n\nReal text."
        #expect(readmeSummary(md) == "Real text.")
    }

    @Test func summaryTruncatesAtWordBoundary() throws {
        let md = String(repeating: "word ", count: 60)
        let summary = try #require(readmeSummary(md))
        #expect(summary.count <= 161)
        #expect(summary.hasSuffix("…"))
        #expect(!summary.dropLast().hasSuffix(" "))
    }
}
