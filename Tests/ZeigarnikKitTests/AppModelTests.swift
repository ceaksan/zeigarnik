import Foundation
import Testing
@testable import ZeigarnikKit

@MainActor @Suite struct AppModelTests {
    let store: Store
    let calendar = zeigarnikCalendar(timeZone: TimeZone(identifier: "Etc/GMT-3")!, locale: Locale(identifier: "en_GB"))
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("zg-model-\(UUID().uuidString)")
    let orbit: String
    let lumen: String

    init() throws {
        store = try Store.inMemory()
        orbit = try store.upsertProject(resolution: .new, path: "/r/02_Products/orbit", displayName: "orbit", identity: nil)
        lumen = try store.upsertProject(resolution: .new, path: "/r/lumen", displayName: "lumen", identity: nil)
    }

    func model() -> AppModel {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        return AppModel(store: store, settings: AppSettings(roots: ["/r"], vaultRoot: nil, calendarId: nil, launchAtLogin: false),
                        coordinator: nil, calendarSync: nil, home: home, now: { now }, calendar: calendar)
    }

    @Test func noteFromDayDetailUsesClickedDay() throws {
        let m = model()
        m.selectedDay = "2026-11-12"
        try m.addNote(text: "eski gün", projectId: orbit, context: .dayDetail)
        #expect(try store.notes(projectId: orbit).map(\.day) == ["2026-11-12"])
    }

    @Test func noteFromProjectDetailUsesToday() throws {
        let m = model()
        m.selectedDay = "2026-11-12"
        try m.addNote(text: "bugün", projectId: orbit, context: .projectDetail)
        #expect(try store.notes(projectId: orbit).map(\.day) == ["2026-11-19"])
    }

    @Test func dayDetailNoteNeedsProjectWhenDayHasSeveral() async throws {
        try store.replaceCommitDays(projectId: orbit, ["2026-11-12": 1])
        try store.replaceCommitDays(projectId: lumen, ["2026-11-12": 2])
        let m = model()
        await m.reload()
        #expect(m.notePrefillProject(day: "2026-11-12") == nil)
        #expect(throws: ModelError.projectRequired) { try m.addNote(text: "x", projectId: nil, context: .dayDetail) }
        #expect(throws: ModelError.emptyText) { try m.addNote(text: " ", projectId: orbit, context: .dayDetail) }
    }

    @Test func dayDetailPrefillsOnlyProject() async throws {
        try store.replaceCommitDays(projectId: orbit, ["2026-11-12": 1])
        let m = model()
        await m.reload()
        #expect(m.notePrefillProject(day: "2026-11-12") == orbit)
        #expect(m.notePrefillProject(day: "2026-11-13") == nil)
    }

    @Test func scheduleWithoutProjectIsRejected() throws {
        let m = model()
        let start = Date(timeIntervalSince1970: 1_763_632_800)
        #expect(throws: ModelError.projectRequired) {
            try m.saveSchedule(ScheduleDraft(id: nil, projectId: nil, title: "x", start: start, duration: 3600, addToCalendar: true))
        }
        #expect(throws: ModelError.invalidDuration) {
            try m.saveSchedule(ScheduleDraft(id: nil, projectId: orbit, title: "x", start: start, duration: 0, addToCalendar: true))
        }
        try m.saveSchedule(ScheduleDraft(id: nil, projectId: orbit, title: "  ", start: start, duration: 3600, addToCalendar: false))
        #expect(try store.scheduledItems(projectId: orbit).map(\.title) == ["orbit"])
    }

    @Test func goToDateSwitchesToCalendarMonthAndDay() {
        let m = model()
        m.goTo(day: "2025-03-14")
        #expect(m.view == .calendar)
        #expect(m.visibleYear == 2025)
        #expect(m.visibleMonth == 3)
        #expect(m.selectedDay == "2025-03-14")
        m.showMonth(offset: -3)
        #expect(m.visibleYear == 2024)
        #expect(m.visibleMonth == 12)
    }

    @Test func visibleRowsFilterThenSearchThenSort() async throws {
        let orbital = try store.upsertProject(resolution: .new, path: "/r/02_Products/orbital", displayName: "orbital", identity: nil)
        for (id, dirty) in [(orbit, 3), (orbital, 9), (lumen, 5)] {
            try store.writeSnapshot(ProjectSnapshot(projectId: id, day: "2026-11-19", scannedAt: Date(), status: GitStatus(
                branch: "main", upstream: "origin/main", ahead: 0, behind: 0, changed: dirty, untracked: 0, stash: 0),
                fetch: nil, lastFetchAt: nil, lastCommitAt: nil, readme: nil, spec: nil, activeTasksOpen: nil, error: nil))
        }
        let m = model()
        await m.reload()
        m.sidebar = .filter(.uncommitted)
        m.searchText = "orb"
        m.sortKey = .dirty
        m.sortAscending = false
        #expect(m.visibleRows.map(\.displayName) == ["orbital", "orbit"])
        #expect(m.counts[.uncommitted] == 3)
    }

    @Test func pinningKeepsVisibilityAndArchitecture() async throws {
        try store.writeVisibility(projectId: orbit, VisibilityCheck(visibility: .public, checkedAt: Date(timeIntervalSince1970: 1_763_550_000)))
        try store.writeSnapshot(ProjectSnapshot(projectId: orbit, day: "2026-11-19", scannedAt: Date(timeIntervalSince1970: 1_763_550_000), status: nil, fetch: nil,
                                                lastFetchAt: nil, lastCommitAt: nil, readme: nil, spec: nil, activeTasksOpen: nil, error: nil,
                                                architecture: .current(path: "architecture.md", updatedAt: nil, commitsSince: 2)))
        let m = model()
        await m.reload()
        let before = try #require(m.row(orbit))
        #expect(before.visibility == .public)
        #expect(before.architecture != nil)
        m.togglePin(orbit)
        let after = try #require(m.row(orbit))
        #expect(after.pinned)
        #expect(after.visibility == .public)
        #expect(after.architecture == before.architecture)
    }

    @Test func finishedScanReloadsOpenDetails() async {
        let m = model()
        let before = m.revision
        await m.scanFinished()
        #expect(m.revision > before)
    }

    @Test func togglePinUpdatesRowAndStore() async throws {
        let m = model()
        await m.reload()
        m.togglePin(orbit)
        #expect(m.rows.first { $0.id == orbit }?.pinned == true)
        #expect(try store.projectRows(today: "2026-11-19", gap: 900).first { $0.id == orbit }?.pinned == true)
    }
}

@Suite struct AppSettingsTests {
    @Test func firstRunNeverSuggestsFolders() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zg-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = AppSettings.firstRun(home: home, fileManager: .default)
        #expect(settings.roots == [])
        #expect(settings.vaultRoot == nil)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Documents/Projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/vault"), withIntermediateDirectories: true)
        let later = AppSettings.firstRun(home: home, fileManager: .default)
        #expect(later.roots == [])
        #expect(later.vaultRoot == nil)
    }

    @Test func settingsRoundTrip() throws {
        let suite = "zg-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let home = URL(fileURLWithPath: "/nonexistent-home")
        #expect(store.load(home: home).roots == [])
        let settings = AppSettings(roots: ["/a", "/b"], vaultRoot: "/v", calendarId: "cal", launchAtLogin: true)
        store.save(settings)
        #expect(store.load(home: home) == settings)
    }

    @Test func scanConfigFollowsSettings() {
        let home = URL(fileURLWithPath: "/h")
        let config = scanConfig(from: AppSettings(roots: ["/a"], vaultRoot: nil, calendarId: nil, launchAtLogin: false), home: home)
        #expect(config.roots.map(\.path) == ["/a"])
        #expect(config.projectTableFile.path == "/a/CLAUDE.md")
        #expect(config.vaultRoot.path == "/h/.zeigarnik-no-vault")
        #expect(config.claudeHome.path == "/h/.claude")
        #expect(config.hcPath == "/h/.local/bin/hc")
    }
}
