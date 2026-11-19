import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct VisibilityKitTests {
    let ctx = FilterContext(now: Date(timeIntervalSince1970: 1_763_550_000), openNow: nil, roots: ["/r"])

    @Test func visibilityCheckIsOnUnlessTurnedOffAndReachesTheScan() throws {
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"roots":["/a"]}"#.utf8))
        #expect(saved.checkVisibility)
        var settings = saved
        #expect(scanConfig(from: settings, home: URL(fileURLWithPath: "/h")).checkVisibility)
        settings.checkVisibility = false
        #expect(!scanConfig(from: settings, home: URL(fileURLWithPath: "/h")).checkVisibility)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.checkVisibility)
    }

    @Test func onlyTheAppTreatsRemovedFoldersAsMissing() {
        let home = URL(fileURLWithPath: "/h")
        #expect(scanConfig(from: AppSettings(roots: ["/a"], vaultRoot: nil, calendarId: nil, launchAtLogin: false), home: home).markRemovedRoots)
        #expect(!ScanConfig.standard(roots: [URL(fileURLWithPath: "/a")], vaultRoot: nil, home: home).markRemovedRoots)
    }

    @Test func turningTheCheckOnRescansWithoutFetch() {
        var off = AppSettings(roots: ["/a"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)
        off.checkVisibility = false
        var on = off
        on.checkVisibility = true
        #expect(SettingsEffects(from: off, to: on) == SettingsEffects(rescan: true, fetch: false, calendarChanged: false, loginChanged: false, visibilityChanged: true))
        // Turning it off asks nothing new, but the running scanner must be replaced or it keeps probing.
        let offEffects = SettingsEffects(from: on, to: off)
        #expect(offEffects == SettingsEffects(rescan: false, fetch: false, calendarChanged: false, loginChanged: false, visibilityChanged: true))
        #expect(offEffects.rebuildScanner)
        #expect(!SettingsEffects(from: on, to: on).rebuildScanner)
    }

    @Test func publicFilterTakesActivePublicReposOnly() {
        #expect(matches(row("a", visibility: .public), .publicRepo, ctx))
        #expect(!matches(row("a", visibility: .private), .publicRepo, ctx))
        #expect(!matches(row("a", visibility: .unknown), .publicRepo, ctx))
        #expect(!matches(row("a"), .publicRepo, ctx))
        #expect(!matches(row("a", state: .missing, visibility: .public), .publicRepo, ctx))
        let counts = filterCounts([row("a", visibility: .public), row("b", visibility: .private), row("c")], ctx)
        #expect(counts[.publicRepo] == 1)
    }

    @Test func visibilityTexts() {
        #expect(Format.visibility(.public) == "public")
        #expect(Format.visibility(.private) == "private")
        #expect(Format.visibility(.unknown) == "unknown")
        #expect(Format.visibility(nil) == "-")
    }

    @Test func sortingByVisibilityPutsUncheckedLast() {
        let rows = [row("u", visibility: .unknown), row("pub", visibility: .public), row("none"), row("priv", visibility: .private)]
        #expect(sorted(rows, by: .visibility, ascending: true).map(\.id) == ["priv", "pub", "none", "u"])
        #expect(sorted(rows, by: .visibility, ascending: false).map(\.id) == ["pub", "priv", "none", "u"])
    }
}
