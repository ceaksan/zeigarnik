import Testing
@testable import ZeigarnikKit

@Suite struct SettingsEffectsTests {
    let base = AppSettings(roots: ["/a"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)

    @Test func addingRootRescansWithFetch() {
        var next = base
        next.roots.append("/b")
        #expect(SettingsEffects(from: base, to: next) == SettingsEffects(rescan: true, fetch: true, calendarChanged: false, loginChanged: false))
    }

    @Test func removingAllRootsRescansWithoutFetch() {
        var next = base
        next.roots = []
        #expect(SettingsEffects(from: base, to: next) == SettingsEffects(rescan: true, fetch: false, calendarChanged: false, loginChanged: false))
    }

    @Test func vaultChangeRescansWithoutFetch() {
        var next = base
        next.vaultRoot = "/vault"
        #expect(SettingsEffects(from: base, to: next) == SettingsEffects(rescan: true, fetch: false, calendarChanged: false, loginChanged: false))
    }

    @Test func calendarAndLoginChangesDoNotRescan() {
        var next = base
        next.calendarId = "C1"
        next.launchAtLogin = true
        #expect(SettingsEffects(from: base, to: next) == SettingsEffects(rescan: false, fetch: false, calendarChanged: true, loginChanged: true))
    }

    @Test func unchangedSettingsDoNothing() {
        #expect(SettingsEffects(from: base, to: base) == SettingsEffects(rescan: false, fetch: false, calendarChanged: false, loginChanged: false))
    }
}
