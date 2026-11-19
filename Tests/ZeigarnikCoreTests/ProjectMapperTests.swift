import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("ProjectMapper")
struct ProjectMapperTests {
    @Test func longestPrefixWithPathBoundary() {
        let mapper = ProjectMapper(
            projects: [(id: "a", path: "/r/a"), (id: "b", path: "/r/a/b")],
            home: "/Users/u", workspaceRoot: "/r"
        )
        #expect(mapper.map("/r/a/b/c") == .project("b"))
        #expect(mapper.map("/r/a/b") == .project("b"))
        #expect(mapper.map("/r/a") == .project("a"))
        #expect(mapper.map("/r/ab") == .other("/r/ab"))
    }

    @Test func mapperNormalizesUnicodeAndSpaces() {
        let projectPath = "/r/Türkçe Tarifler".decomposedStringWithCanonicalMapping
        let mapper = ProjectMapper(
            projects: [(id: "turkish", path: projectPath), (id: "spaces", path: "/r/with space")],
            home: "/Users/u", workspaceRoot: "/r"
        )
        #expect(mapper.map("/r/Türkçe Tarifler".precomposedStringWithCanonicalMapping) == .project("turkish"))
        #expect(mapper.map("/r/with space/x") == .project("spaces"))
    }

    @Test func otherBucketLabels() {
        let mapper = ProjectMapper(
            projects: [], home: "/Users/u", workspaceRoot: "/Users/u/Code"
        )
        #expect(mapper.map("/Users/u/Code") == .other("Code"))
        #expect(mapper.map("/Users/u/Desktop/x") == .other("~/Desktop/x"))
        #expect(mapper.map("/Users/u") == .other("~"))
        #expect(mapper.map("/Users/uncle/Desktop/x") == .other("/Users/uncle/Desktop/x"))
        #expect(mapper.map("/Volumes/Archive/project") == .other("/Volumes/Archive/project"))
    }

    @Test func mainAndWorktreePathsShareProjectIdentity() {
        let mapper = ProjectMapper(
            projects: [
                (id: "a", path: "/r/a"),
                (id: "a", path: "/r/a/.worktrees/nested"),
                (id: "a", path: "/r/a-feature"),
            ],
            home: "/Users/u", workspaceRoot: "/r"
        )
        #expect(mapper.map("/r/a/src") == .project("a"))
        #expect(mapper.map("/r/a/.worktrees/nested/src") == .project("a"))
        #expect(mapper.map("/r/a-feature/src") == .project("a"))
        #expect(mapper.map("/r/a-feature-extra") == .other("/r/a-feature-extra"))
    }

    @Test func standardizesPathsBeforeMatching() {
        let mapper = ProjectMapper(
            projects: [(id: "a", path: "/r/parent/../a/")],
            home: "/Users/u/", workspaceRoot: "/r/"
        )
        #expect(mapper.map("/r/a/./src/../file.swift") == .project("a"))
        #expect(mapper.map("/Users/u/Desktop/../Documents/x") == .other("~/Documents/x"))
    }
}
