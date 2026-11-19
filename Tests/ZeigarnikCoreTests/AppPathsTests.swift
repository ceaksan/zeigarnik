import Foundation
import Testing
@testable import ZeigarnikCore

@Suite struct AppPathsTests {
    @Test func databaseURLMatchesCLIDefault() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(AppPaths.databaseURL(home: home).path == "/Users/someone/Library/Application Support/Zeigarnik/zeigarnik.sqlite")
    }

    @Test func ensureCreatesDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zg-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = try AppPaths.ensureDatabaseDirectory(home: home)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDir) && isDir.boolValue)
        #expect(url == AppPaths.databaseURL(home: home))
    }
}
