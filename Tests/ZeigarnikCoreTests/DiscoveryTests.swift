import Foundation
import Testing
@testable import ZeigarnikCore

@Suite("Discovery")
struct DiscoveryTests {
    private func makeTree() throws -> URL {
        let root = try makeTempDir()
        let fm = FileManager.default
        func dir(_ path: String) throws { try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
        try dir("a/.git")
        try dir("b")
        try Data("gitdir: /elsewhere/.git/worktrees/b\n".utf8).write(to: root.appendingPathComponent("b/.git"))
        try dir("a/nested/.git")
        try dir("x/y/z/w/v/.git")
        try dir("node_modules/p/.git")
        try dir(".hidden/q/.git")
        try dir("with space/ç/.git")
        return root
    }

    @Test func findsDirAndFileGitButNotNestedDeepOrSkipped() throws {
        let root = try makeTree()
        let result = discoverRepositories(roots: [root])
        #expect(result.repos.map(\.lastPathComponent) == ["a", "b", "ç"])
        #expect(result.enumeratedRoots == [root.standardizedFileURL])
        #expect(result.errors.isEmpty)
    }

    @Test func unreadableRootIsReported() {
        let missing = URL(fileURLWithPath: "/nonexistent-zg-\(UUID().uuidString)")
        let result = discoverRepositories(roots: [missing])
        #expect(result.repos.isEmpty)
        #expect(result.enumeratedRoots.isEmpty)
        #expect(result.errors.count == 1)
    }
}
