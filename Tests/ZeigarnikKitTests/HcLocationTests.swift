import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct HcLocationTests {
    let home = URL(fileURLWithPath: "/Users/example")

    @Test func firstInstalledLocationWins() {
        let installed: Set<String> = ["/opt/homebrew/bin/hc", "/usr/local/bin/hc"]
        #expect(hcPath(home: home, isExecutable: { installed.contains($0) }) == "/opt/homebrew/bin/hc")
    }

    @Test func userBinComesFirstAndIsTheDefaultWhenNothingIsInstalled() {
        #expect(hcPath(home: home, isExecutable: { _ in true }) == "/Users/example/.local/bin/hc")
        #expect(hcPath(home: home, isExecutable: { _ in false }) == "/Users/example/.local/bin/hc")
    }

    @Test func scanConfigUsesTheResolvedLocation() {
        let settings = AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)
        #expect(scanConfig(from: settings, home: home, isExecutable: { $0 == "/usr/local/bin/hc" }).hcPath == "/usr/local/bin/hc")
    }
}
