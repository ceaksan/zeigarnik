import Foundation
import Testing
@testable import ZeigarnikKit

@Suite struct AdvancedSettingsTests {
    let base = AppSettings(roots: ["/a"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)

    @Test func savedSettingsWithoutAdvancedKeysKeepTheSpecDefaults() throws {
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"roots":["/a"]}"#.utf8))
        #expect(saved.scanIntervalHours == 2)
        #expect(saved.activityGapMinutes == 15)
        #expect(saved.scanInterval == .seconds(7200))
        #expect(scanConfig(from: saved, home: URL(fileURLWithPath: "/h")).gap == 900)
    }

    @Test func advancedValuesRoundTripAndReachTheScan() throws {
        var settings = base
        settings.scanIntervalHours = 4
        settings.activityGapMinutes = 10
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.scanIntervalHours == 4)
        #expect(decoded.activityGapMinutes == 10)
        #expect(decoded.scanInterval == .seconds(14_400))
        #expect(scanConfig(from: decoded, home: URL(fileURLWithPath: "/h")).gap == 600)
    }

    @Test func outOfRangeSavedValuesFallBackToDefaults() throws {
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"roots":["/a"],"scanIntervalHours":0,"activityGapMinutes":-5}"#.utf8))
        #expect(saved.scanIntervalHours == 2)
        #expect(saved.activityGapMinutes == 15)
    }

    @Test func gapChangeReloadsWithoutRescanAndIntervalChangeOnlyRetimes() {
        var gap = base
        gap.activityGapMinutes = 10
        #expect(SettingsEffects(from: base, to: gap) == SettingsEffects(rescan: false, fetch: false, calendarChanged: false, loginChanged: false, reload: true))
        var interval = base
        interval.scanIntervalHours = 8
        #expect(SettingsEffects(from: base, to: interval) == SettingsEffects(rescan: false, fetch: false, calendarChanged: false, loginChanged: false, intervalChanged: true))
    }
}

@MainActor @Suite struct AdvancedSettingsModelTests {
    @Test func activityGapSettingDecidesWhatCountsAsWorkTime() async throws {
        let store = try Store.inMemory()
        let calendar = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_GB"))
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9))!
        let messages = [0, 12 * 60].map {
            OwnerMessage(agent: .claude, sessionId: "s1", timestamp: start.addingTimeInterval(TimeInterval($0)), cwd: "/r/tool", source: .history)
        }
        try store.ingest(IngestBatch(messages: messages, sessions: [], codexHeaders: [], cursor: nil))
        var settings = AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false)
        let model = AppModel(store: store, settings: settings, coordinator: nil, calendarSync: nil,
                             home: URL(fileURLWithPath: "/nonexistent-home"), now: { start.addingTimeInterval(3600) }, calendar: calendar)
        await model.reload()
        #expect(model.activity.dayTotal("2026-11-19") == 720)
        settings.activityGapMinutes = 10
        model.updateSettings(settings)
        await model.reload()
        #expect(model.activity.dayTotal("2026-11-19") == 0)
    }

    @Test func timerFollowsTheIntervalSetting() async {
        let scanner = FakeScanner()
        await scanner.setBlocking(false)
        let coordinator = ScanCoordinator(scanner: scanner, interval: .milliseconds(30), step: .milliseconds(10), openNowProvider: nil) { _ in }
        coordinator.start()
        await eventually { await scanner.calls.count >= 3 }
        #expect(await scanner.calls.count >= 3)
        coordinator.setInterval(.seconds(3600))
        try? await Task.sleep(for: .milliseconds(60))
        let settled = await scanner.calls.count
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await scanner.calls.count == settled)
        coordinator.stop()
    }
}
