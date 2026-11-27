import Foundation
import Testing
@testable import ZeigarnikCore

private let manifestSamples: [(String, String)] = [
    ("package.json", #"{"name":"orbit","version":"VERSION","dependencies":{"lumen":"DEPENDENCY"}}"#),
    ("pyproject.toml", "[project]\nname = \"orbit\"\nversion = \"VERSION\"\ndependencies = [\n  \"lumen>=DEPENDENCY\",\n]\n"),
    ("Cargo.toml", "[package]\nname = \"orbit\"\nversion = \"VERSION\"\n[dependencies]\nlumen = \"DEPENDENCY\"\n"),
    ("Package.swift", "// swift-tools-version: 6.0\nimport PackageDescription\nlet version = \"VERSION\"\nlet package = Package(name: \"orbit\", dependencies: [.package(url: \"https://example.com/lumen.git\", from: \"DEPENDENCY\")])\n"),
]

@Suite("ManifestDrift")
struct ManifestDriftTests {
    @Test func C12_dynamicAndMalformedManifestsStayConservative() {
        #expect(dependencySignature("let package = Package(name: \"orbit\", dependencies: dependencies)", name: "Package.swift") == nil)
        #expect(dependencySignature("let package = Package(name: \"orbit\", dependencies: [] + extra)", name: "Package.swift") == nil)
        #expect(dependencySignature("[project]\ndynamic = [\"dependencies\"]\n", name: "pyproject.toml") == nil)
        #expect(dependencySignature("[dependencies]\nlumen = [", name: "Cargo.toml") == nil)
        #expect(dependencySignature("{", name: "package.json") == nil)
        #expect(dependencySignature("lumen>=1", name: "requirements.txt") == nil)
    }

    @Test func C12_quotedAndGroupedDependenciesAreCompared() {
        for name in ["Cargo.toml", "pyproject.toml"] {
            let before = "[\"dependencies\"]\nlumen = \"1\"\n"
            let after = "[\"dependencies\"]\nlumen = \"2\"\n"
            #expect(dependencySignature(before, name: name) != dependencySignature(after, name: name))
        }
        #expect(dependencySignature("[dependency-groups]\ntest = [\"lumen\"]\n", name: "pyproject.toml") != dependencySignature("[dependency-groups]\ntest = [\"harbor\"]\n", name: "pyproject.toml"))
    }

    @Test(arguments: manifestSamples)
    func C12_versionOnlyChangesDoNotMakeReadmeBehind(name: String, template: String) async throws {
        // Discovery looks for repositories under a root, so the repository sits one level below it.
        let root = try makeTempDir()
        let repo = root.appendingPathComponent("orbit", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        await runGit(repo, ["init", "-q"])
        func write(version: String, dependency: String) throws {
            let text = template.replacingOccurrences(of: "VERSION", with: version).replacingOccurrences(of: "DEPENDENCY", with: dependency)
            try Data(text.utf8).write(to: repo.appendingPathComponent(name))
        }
        try write(version: "1.0.0", dependency: "1.0.0")
        try Data("# Orbit\nSynthetic baseline.\n".utf8).write(to: repo.appendingPathComponent("README.md"))
        await runGit(repo, ["add", "README.md", name])
        await runGit(repo, ["commit", "-q", "-m", "document dependencies"])
        for version in ["1.0.1", "1.0.2", "1.0.3"] {
            try write(version: version, dependency: "1.0.0")
            await runGit(repo, ["add", name])
            await runGit(repo, ["commit", "-q", "-m", "synthetic release"])
        }
        let store = try Store.inMemory()
        let home = try makeTempDir()
        let scanner = makeTestScanner(config: .standard(roots: [root], vaultRoot: nil, home: home), store: store, runner: ProcessRunner())
        let first = await scanner.scan(fetch: false)
        #expect(first.errors.isEmpty)
        let today = dayKey(Date(), calendar: .current)
        #expect(try store.projectRows(today: today, gap: 900).first?.readme == .current)
        try write(version: "1.0.3", dependency: "2.0.0")
        await runGit(repo, ["add", name])
        await runGit(repo, ["commit", "-q", "-m", "change dependency"])
        _ = await scanner.scan(fetch: false)
        guard case .behind(_, _, let changed)? = try store.projectRows(today: today, gap: 900).first?.readme else {
            Issue.record("A dependency change must still make the README behind")
            return
        }
        #expect(changed)
    }
}
