import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct ArchitectureDocTests {
    func commit(_ day: Int, _ files: [String]) -> CommitRecord {
        CommitRecord(hash: "c\(day)", parents: [], authorDate: Date(timeIntervalSince1970: Double(day) * 86_400), subject: "s", files: files)
    }

    /// Newest first: the doc was written on day 2 with the code it describes.
    func history(_ newer: [CommitRecord]) -> [CommitRecord] {
        newer + [commit(2, ["architecture.md", "Sources/App/main.swift", "Package.swift"]), commit(1, ["README.md", "Sources/App/util.swift"])]
    }

    @Test func findsRootFirstThenDocsInAnyCase() {
        #expect(findArchitectureDoc(in: ["ARCHITECTURE.md", "docs/architecture.md"]) == "ARCHITECTURE.md")
        #expect(findArchitectureDoc(in: ["docs/Architecture.md", "README.md"]) == "docs/Architecture.md")
        #expect(findArchitectureDoc(in: ["src/architecture.md", "README.md"]) == nil)
    }

    @Test func noDocumentIsNone() {
        #expect(architectureDoc(history: history([]), path: nil) == .none)
    }

    @Test func editsToExistingCodeKeepItCurrent() {
        let doc = architectureDoc(history: history([commit(4, ["Sources/App/main.swift"]), commit(3, ["Sources/App/util.swift"])]), path: "architecture.md")
        #expect(doc == .current(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 2))
    }

    @Test func aNewModuleFolderMakesItBehind() {
        let doc = architectureDoc(history: history([commit(3, ["Sources/Sync/engine.swift"])]), path: "architecture.md")
        #expect(doc == .behind(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 1,
                               newDirectories: ["Sources/Sync"], newFiles: 1, manifestChanged: false))
    }

    @Test func fiveNewFilesInKnownFoldersMakeItBehindFourDoNot() {
        let four = (1...4).map { "Sources/App/f\($0).swift" }
        #expect(architectureDoc(history: history([commit(3, four)]), path: "architecture.md")
                == .current(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 1))
        let five = four + ["Sources/App/f5.swift"]
        #expect(architectureDoc(history: history([commit(3, five)]), path: "architecture.md")
                == .behind(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 1,
                           newDirectories: [], newFiles: 5, manifestChanged: false))
    }

    @Test func manifestChangeMakesItBehind() {
        let doc = architectureDoc(history: history([commit(3, ["Package.swift"])]), path: "architecture.md")
        #expect(doc == .behind(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 1,
                               newDirectories: [], newFiles: 0, manifestChanged: true))
    }

    @Test func docsMarkdownAndDotFoldersAreIgnored() {
        let doc = architectureDoc(history: history([commit(3, ["docs/guide/a.md", "NOTES.md", ".github/workflows/ci.yml", "docs/img/x.png"])]), path: "architecture.md")
        #expect(doc == .current(path: "architecture.md", updatedAt: Date(timeIntervalSince1970: 2 * 86_400), commitsSince: 1))
    }

    @Test func uncommittedDocumentIsCurrentWithUnknownDate() {
        #expect(architectureDoc(history: history([]), path: "docs/architecture.md") == .current(path: "docs/architecture.md", updatedAt: nil, commitsSince: 0))
    }
}
