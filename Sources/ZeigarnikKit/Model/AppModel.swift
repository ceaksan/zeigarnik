import Foundation
import Observation

public enum MainView: Sendable { case list, calendar }
public enum SidebarSelection: Hashable, Sendable { case filter(ProjectFilter), other }
public enum NoteContext: Sendable { case projectDetail, dayDetail }
public enum ModelError: Error, Equatable { case projectRequired, emptyText, invalidDuration }

public struct ScheduleDraft: Sendable, Equatable {
    public var id: UUID?
    public var projectId: String?
    public var title: String
    public var start: Date
    public var duration: TimeInterval
    public var addToCalendar: Bool

    public init(id: UUID?, projectId: String?, title: String, start: Date, duration: TimeInterval, addToCalendar: Bool) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.start = start
        self.duration = duration
        self.addToCalendar = addToCalendar
    }
}

public struct ProjectDetail: Sendable, Equatable {
    public init(notes: [Note] = [], items: [ScheduledItem] = [], specs: [SpecSummary] = [], drafts: [NoteDraft] = []) {
        self.notes = notes
        self.items = items
        self.specs = specs
        self.drafts = drafts
    }

    public var notes: [Note] = []
    /// Drafts from the project's state that the owner has not accepted or dismissed (ADR-006).
    public var drafts: [NoteDraft] = []
    public var items: [ScheduledItem] = []
    public var specs: [SpecSummary] = []
}

public struct DayDetail: Sendable, Equatable {
    public init(notes: [Note] = [], items: [ScheduledItem] = []) {
        self.notes = notes
        self.items = items
    }

    public var notes: [Note] = []
    public var items: [ScheduledItem] = []
}

public struct MonthOwnerData: Sendable, Equatable {
    public init(notes: [String: [Note]] = [:], items: [String: [ScheduledItem]] = [:]) {
        self.notes = notes
        self.items = items
    }

    public var notes: [String: [Note]] = [:]
    public var items: [String: [ScheduledItem]] = [:]
}

/// UI state and owner-data actions. Store reads run off the main actor; small owner-data writes run inline.
@MainActor @Observable
public final class AppModel {
    public private(set) var rows: [ProjectRow] = []
    public private(set) var activity: ActivityIndex = .empty
    public private(set) var sourceProblems: [SourceProblem] = []
    /// Set when the last reload could not read the database; the previous rows stay on screen.
    public private(set) var loadError: String?
    /// Set when reading or writing notes, schedules, pins or spec marks fails, so a failure never looks like empty data.
    public private(set) var ownerDataError: String?
    @ObservationIgnored private var ownerErrorFromRead = false
    public private(set) var isLoaded = false
    public private(set) var settings: AppSettings
    /// Bumped after every owner-data change; views reload their detail with `.task(id:)` on it.
    public private(set) var revision = 0

    public var view: MainView = .list
    public var sidebar: SidebarSelection = .filter(.all)
    public var searchText = ""
    public var sortKey: ProjectSortKey = .lastActivity
    public var sortAscending = false
    public var selectedProjectId: String?
    public var selectedDay: String
    public var visibleYear: Int
    public var visibleMonth: Int

    public let calendar: Calendar
    public let coordinator: ScanCoordinator?
    public let calendarSync: CalendarSync?
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var lastDataVersion: Int?
    public var gap: TimeInterval { settings.activityGap }

    public init(store: Store, settings: AppSettings, coordinator: ScanCoordinator?, calendarSync: CalendarSync?,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = zeigarnikCalendar()) {
        self.store = store
        self.settings = settings
        self.coordinator = coordinator
        self.calendarSync = calendarSync
        self.home = home
        self.now = now
        self.calendar = calendar
        let today = now()
        selectedDay = dayKey(today, calendar: calendar)
        visibleYear = calendar.component(.year, from: today)
        visibleMonth = calendar.component(.month, from: today)
    }

    // MARK: Derived state

    public var today: String { dayKey(now(), calendar: calendar) }
    public var currentDate: Date { now() }

    public var filterContext: FilterContext {
        FilterContext(now: now(), openNow: coordinator?.openNow, roots: settings.roots)
    }

    public var visibleRows: [ProjectRow] {
        guard case .filter(let filter) = sidebar else { return [] }
        let context = filterContext
        return sorted(search(rows.filter { matches($0, filter, context) }, searchText), by: sortKey, ascending: sortAscending)
    }

    public var counts: [ProjectFilter: Int] { filterCounts(rows, filterContext) }

    public func row(_ id: String) -> ProjectRow? { rows.first { $0.id == id } }

    public func displayName(_ id: String) -> String {
        row(id)?.displayName ?? (try? store.displayName(projectId: id)) ?? id
    }

    // MARK: Loading

    public func reload() async {
        let generation = beginReload()
        let store = self.store
        let settings = self.settings
        let home = self.home
        let today = self.today
        let calendar = self.calendar
        let gap = self.gap
        let checks = draftChecks
        let loaded = await Task.detached(priority: .userInitiated) { () -> (Result<([ProjectRow], ActivityIndex), any Error>, [SourceProblem]) in
            let data = Result {
                let rows = try store.projectRows(today: today, gap: gap)
                // Forgets dismissals whose state cleared, so it shows again when it returns, even if the project was never opened.
                _ = try? store.openNoteDrafts(rows.flatMap { noteDrafts(for: $0, checks: checks) }, projectIds: Set(rows.map(\.id)))
                let index = buildActivityIndex(messages: try store.effectiveMessages(), commitDays: try store.commitDays(),
                                               calendar: calendar, gap: gap)
                return (rows, index)
            }
            let problems = checkSources(scanConfig(from: settings, home: home), vaultConfigured: settings.vaultRoot != nil)
            return (data, problems)
        }.value
        finishReload(generation, data: loaded.0, problems: loaded.1)
    }

    func beginReload() -> Int {
        reloadGeneration += 1
        return reloadGeneration
    }

    /// Reloads overlap (scan end, settings change, timer); a slower older read must not replace a newer one.
    func finishReload(_ generation: Int, data: Result<([ProjectRow], ActivityIndex), any Error>, problems: [SourceProblem]) {
        guard generation == reloadGeneration else { return }
        switch data {
        case .success(let data):
            rows = data.0
            activity = data.1
            loadError = nil
        case .failure(let error):
            loadError = "Could not read projects from the database; showing the last loaded list: \(error)"
        }
        sourceProblems = problems
        isLoaded = true
    }

    /// Called when a scan finishes: rows reload, and open details reload too, since scans apply spec overrides.
    public func scanFinished() async {
        await reload()
        revision += 1
    }

    public func projectDetail(_ id: String) async -> ProjectDetail {
        let store = self.store
        let candidates = row(id).map { noteDrafts(for: $0, checks: draftChecks) } ?? []
        let loaded: Set<String> = row(id) == nil ? [] : [id]
        return await readOwnerData(ProjectDetail()) {
            ProjectDetail(notes: try store.notes(projectId: id), items: try store.scheduledItems(projectId: id),
                          specs: try store.specSummaries(projectId: id), drafts: try store.openNoteDrafts(candidates, projectIds: loaded))
        }
    }

    private var draftChecks: NoteDraftChecks {
        NoteDraftChecks(readme: settings.checkReadme, architecture: settings.checkArchitecture)
    }

    public func dayDetail(_ day: String) async -> DayDetail {
        let store = self.store
        guard let range = dayRange(day) else { return DayDetail() }
        return await readOwnerData(DayDetail()) {
            DayDetail(notes: try store.notes(fromDay: day, toDay: day), items: try store.scheduledItems(from: range.start, to: range.end))
        }
    }

    public func monthOwnerData(fromDay: String, toDay: String) async -> MonthOwnerData {
        let store = self.store
        let calendar = self.calendar
        guard let start = dayRange(fromDay)?.start, let end = dayRange(toDay)?.end else { return MonthOwnerData() }
        return await readOwnerData(MonthOwnerData()) {
            var data = MonthOwnerData()
            for note in try store.notes(fromDay: fromDay, toDay: toDay) { data.notes[note.day, default: []].append(note) }
            for item in try store.scheduledItems(from: start, to: end) {
                data.items[dayKey(item.start, calendar: calendar), default: []].append(item)
            }
            return data
        }
    }

    public func upcomingItems(days: Int) async -> [ScheduledItem] {
        let store = self.store
        let start = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: days + 1, to: start) else { return [] }
        return await readOwnerData([]) { try store.scheduledItems(from: start, to: end) }
    }

    /// Runs a store read off the main actor; a failure is reported and the empty value shown with the banner.
    private func readOwnerData<T: Sendable>(_ empty: T, _ body: @escaping @Sendable () throws -> T) async -> T {
        let result = await Task.detached { Result { try body() } }.value
        switch result {
        case .success(let value):
            if ownerErrorFromRead { ownerDataError = nil }
            return value
        case .failure(let error):
            ownerFailed("read notes and schedules", error, read: true)
            return empty
        }
    }

    private func ownerFailed(_ action: String, _ error: any Error, read: Bool) {
        ownerDataError = "Could not \(action): \(error)"
        ownerErrorFromRead = read
    }

    /// Runs an owner-data write; success clears any earlier owner-data error.
    private func writeOwnerData(_ action: String, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            ownerDataError = nil
            return true
        } catch {
            ownerFailed(action, error, read: false)
            return false
        }
    }

    // MARK: Owner data

    public func addNote(text: String, projectId: String?, context: NoteContext) throws {
        guard let projectId else { throw ModelError.projectRequired }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError.emptyText }
        let day = context == .dayDetail ? selectedDay : today
        _ = try store.addNote(projectId: projectId, day: day, text: text, now: now())
        revision += 1
    }

    public func updateNote(id: UUID, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError.emptyText }
        _ = try store.updateNote(id: id, text: text)
        revision += 1
    }

    /// Saves the owner's (possibly edited) text as today's note and dismisses the draft.
    public func acceptDraft(_ draft: NoteDraft, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError.emptyText }
        _ = try store.acceptNoteDraft(draft, text: text, day: today, now: now())
        revision += 1
    }

    public func dismissDraft(_ draft: NoteDraft) {
        _ = writeOwnerData("dismiss the draft") { try store.dismissNoteDraft(draft, now: now()) }
        revision += 1
    }

    /// True when another connection (the command-line tool, an agent, `zeigarnik-scan`) committed since the last check;
    /// rows and open details are then reloaded. The first call only records the starting point.
    public func checkExternalChanges() async -> Bool {
        let store = self.store
        guard let version = await Task.detached(operation: { try? store.dataVersion() }).value else { return false }
        guard let last = lastDataVersion else {
            lastDataVersion = version
            return false
        }
        guard version != last else { return false }
        lastDataVersion = version
        await reload()
        revision += 1
        return true
    }

    public func deleteNote(id: UUID) {
        _ = writeOwnerData("delete the note") { try store.deleteNote(id: id) }
        revision += 1
    }

    /// The only project active on that day, else nil so the owner has to pick one.
    public func notePrefillProject(day: String) -> String? {
        let projects = activity.slices(day: day).compactMap { slice -> String? in
            if case .project(let id) = slice.owner { return id }
            return nil
        }
        return projects.count == 1 ? projects[0] : nil
    }

    public func togglePin(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let old = rows[index]
        guard writeOwnerData("change the pin", { try store.setPinned(projectId: id, !old.pinned) }) else { return }
        rows[index] = old.withPinned(!old.pinned)
    }

    public func saveSchedule(_ draft: ScheduleDraft) throws {
        guard let projectId = draft.projectId else { throw ModelError.projectRequired }
        guard draft.duration > 0 else { throw ModelError.invalidDuration }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ScheduledItem(id: draft.id ?? UUID(), projectId: projectId, title: title.isEmpty ? displayName(projectId) : title,
                                 start: draft.start, duration: draft.duration, wantsCalendar: draft.addToCalendar,
                                 eventIdentifier: nil, syncState: .pending, syncDetail: nil, deletedAt: nil)
        try store.saveScheduledItem(item)
        revision += 1
        reconcileCalendar()
    }

    public func deleteSchedule(id: UUID) {
        _ = writeOwnerData("delete the scheduled item") { try store.deleteScheduledItem(id: id, now: now()) }
        revision += 1
        reconcileCalendar()
    }

    public func scheduledItem(id: UUID) -> ScheduledItem? {
        do { return try store.scheduledItem(id: id) } catch {
            ownerFailed("read the scheduled item", error, read: true)
            return nil
        }
    }

    public func setSpecOverride(projectId: String, specPath: String, _ state: OwnerSpecOverride?, note: String?) {
        guard writeOwnerData("save the spec mark", { try store.setSpecOverride(projectId: projectId, specPath: specPath, state, note: note) }) else { return }
        revision += 1
        coordinator?.requestScan(fetch: false)
    }

    public func reconcileCalendar() {
        guard let calendarSync else { return }
        Task { [weak self] in
            _ = await calendarSync.reconcile()
            self?.revision += 1
        }
    }

    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Navigation

    public func goTo(day: String) {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return }
        view = .calendar
        visibleYear = parts[0]
        visibleMonth = parts[1]
        selectedDay = day
    }

    public func showMonth(offset: Int) {
        let total = visibleYear * 12 + (visibleMonth - 1) + offset
        visibleYear = total / 12
        visibleMonth = total % 12 + 1
    }

    public func showToday() {
        goTo(day: today)
    }

    private func dayRange(_ day: String) -> DateInterval? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return calendar.dateInterval(of: .day, for: start)
    }
}
