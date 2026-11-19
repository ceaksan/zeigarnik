import AppKit
import EventKit
import Foundation
import Observation
import ServiceManagement
import ZeigarnikKit

/// Composition root: settings, store, scanner, coordinator and model.
@MainActor @Observable
public final class AppEnvironment {
    public let model: AppModel
    public let coordinator: ScanCoordinator
    public let startupError: String?
    @ObservationIgnored let gateway = EventKitGateway()
    @ObservationIgnored let calendarTarget: CalendarTarget
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    public private(set) var upcoming: [ScheduledItem] = []
    public private(set) var calendarAccess: CalendarAccess = .notDetermined
    public private(set) var calendars: [CalendarInfo] = []
    public private(set) var launchAtLoginError: String?
    public private(set) var terminals: [OpenTarget] = []
    public private(set) var editors: [OpenTarget] = []
    public private(set) var openError: String?
    @ObservationIgnored private let home: URL
    @ObservationIgnored private let runner: ProcessRunner

    public var menubarSummary: MenubarSummary {
        ZeigarnikKit.menubarSummary(rows: model.rows, items: upcoming, lastScanAt: coordinator.lastReport?.finishedAt,
                                    now: model.currentDate, calendar: model.calendar)
    }
    @ObservationIgnored let settingsStore: SettingsStore
    @ObservationIgnored let store: Store
    @ObservationIgnored private var started = false

    public init() {
        var home = FileManager.default.homeDirectoryForCurrentUser
        #if DEBUG
        if let override = LaunchOptions.home(from: ProcessInfo.processInfo.arguments) { home = override }
        #endif
        let settingsStore = SettingsStore(defaults: .standard)
        var settings = settingsStore.load(home: home)
        #if DEBUG
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--settings-json"),
           i + 1 < ProcessInfo.processInfo.arguments.count,
           let override = try? JSONDecoder().decode(AppSettings.self, from: Data(ProcessInfo.processInfo.arguments[i + 1].utf8)) {
            settings = override
        }
        #endif
        var startupError: String?
        let store: Store
        do {
            store = try Store(path: AppPaths.ensureDatabaseDirectory(home: home).path)
        } catch {
            startupError = "Could not open the database; data will only be available for this session: \(error)"
            store = try! Store.inMemory()
        }
        let config = scanConfig(from: settings, home: home)
        let runner = ProcessRunner()
        let scanner = ProjectScanner(config: config, store: store, runner: runner, visibilityProbe: Self.visibilityProbe(runner: runner))
        let relay = ScanRelay()
        let coordinator = ScanCoordinator(scanner: scanner, interval: settings.scanInterval, openNowProvider: Self.openNowProvider(store: store, config: config, runner: runner)) {
            relay.forward($0)
        }
        let calendarTarget = CalendarTarget(settings.calendarId)
        let calendarSync = CalendarSync(store: store, gateway: gateway, targetCalendarId: { calendarTarget.value })
        let model = AppModel(store: store, settings: settings, coordinator: coordinator, calendarSync: calendarSync, home: home)
        relay.model = model
        self.settingsStore = settingsStore
        self.store = store
        self.coordinator = coordinator
        self.model = model
        self.startupError = startupError
        self.calendarTarget = calendarTarget
        self.home = home
        self.runner = runner
        relay.environment = self
        // Scans, timers and calendar reconcile must not wait for the main window: a launch can restore only the menubar extra.
        Task { [weak self] in self?.start() }
    }

    public func start() {
        guard !started else { return }
        started = true
        applyAppearance()
        refreshInstalledApps()
        Task { await model.reload() }
        coordinator.start()
        model.reconcileCalendar()
        refreshUpcoming()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshUpcoming()
            }
        }
        eventObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: gateway.eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.reconcileCalendar()
                self?.refreshSystemState()
            }
        }
    }

    /// Saves a settings change and carries out what it requires: rescan, calendar reconcile, login item.
    public func apply(_ requested: AppSettings) {
        let old = model.settings
        var new = requested
        let effects = SettingsEffects(from: old, to: new)
        if effects.loginChanged { new.launchAtLogin = setLaunchAtLogin(new.launchAtLogin) }
        guard new != old else { return }
        settingsStore.save(new)
        model.updateSettings(new)
        calendarTarget.value = new.calendarId
        if effects.rebuildScanner {
            let config = scanConfig(from: new, home: home)
            coordinator.replaceScanner(ProjectScanner(config: config, store: store, runner: runner, visibilityProbe: Self.visibilityProbe(runner: runner)),
                                       openNowProvider: Self.openNowProvider(store: store, config: config, runner: runner))
        }
        if effects.rescan {
            coordinator.requestScan(fetch: effects.fetch)
            Task { await model.reload() }
        }
        if effects.reload && !effects.rescan { Task { await model.reload() } }
        if effects.intervalChanged { coordinator.setInterval(new.scanInterval) }
        if effects.calendarChanged { model.reconcileCalendar() }
        if new.appearance != old.appearance { applyAppearance() }
    }

    public var terminal: OpenTarget? { terminals.first { $0.bundleId == model.settings.terminalApp } ?? terminals.first }
    public var editor: OpenTarget? { editors.first { $0.bundleId == model.settings.editorApp } ?? editors.first }

    public func open(_ path: String, with target: OpenTarget) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleId) else {
            openError = "\(target.name) is no longer installed."
            refreshInstalledApps()
            return
        }
        openError = nil
        NSWorkspace.shared.open([URL(fileURLWithPath: path, isDirectory: true)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            let message = "Could not open in \(target.name): \(error.localizedDescription)"
            Task { @MainActor [weak self] in self?.openError = message }
        }
    }

    /// herdr is offered only when its `hc` CLI is installed.
    /// `gh` is looked up where Homebrew installs it; apps launched from Finder have no shell PATH.
    static func visibilityProbe(runner: CommandRunning) -> NetworkVisibilityProbe {
        let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
        return NetworkVisibilityProbe(runner: runner, ghPath: gh, httpStatus: { await liveHTTPStatus($0) })
    }

    public var herdrAvailable: Bool { FileManager.default.isExecutableFile(atPath: scanConfig(from: model.settings, home: home).hcPath) }

    public func openInHerdr(_ path: String) {
        openError = nil
        let runner = self.runner
        let hcPath = scanConfig(from: model.settings, home: home).hcPath
        Task {
            if let error = await ZeigarnikKit.openInHerdr(runner: runner, hcPath: hcPath, path: path) {
                openError = error
            } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.herdr.app") {
                _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    public func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func refreshInstalledApps() {
        let installed = { (id: String) in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
        terminals = OpenTarget.available(.terminal, isInstalled: installed)
        editors = OpenTarget.available(.editor, isInstalled: installed)
    }

    private func applyAppearance() {
        NSApp.appearance = switch model.settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Reads calendar access, the calendar list and the real login item state; called when Settings opens.
    public func refreshSystemState() {
        refreshInstalledApps()
        calendarAccess = gateway.access()
        calendars = calendarAccess == .granted ? gateway.calendars() : []
        let registered = Self.loginItemActive(SMAppService.mainApp.status)
        if registered != model.settings.launchAtLogin {
            var settings = model.settings
            settings.launchAtLogin = registered
            settingsStore.save(settings)
            model.updateSettings(settings)
        }
    }

    public func requestCalendarAccess() async {
        _ = await gateway.requestAccess()
        refreshSystemState()
        model.reconcileCalendar()
    }

    private func setLaunchAtLogin(_ on: Bool) -> Bool {
        let service = SMAppService.mainApp
        var failure: String?
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            failure = error.localizedDescription
        }
        let active = Self.loginItemActive(service.status)
        if active != on {
            launchAtLoginError = "Could not change the login item" + (failure.map { ": \($0)" } ?? ".")
        } else if service.status == .requiresApproval {
            launchAtLoginError = "Approve Zeigarnik in System Settings > General > Login Items."
        } else {
            launchAtLoginError = nil
        }
        return active
    }

    private static func loginItemActive(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    public func refreshUpcoming() {
        Task {
            upcoming = await model.upcomingItems(days: 7)
        }
    }

    var calendarTitle: String? {
        guard let id = model.settings.calendarId else { return nil }
        return gateway.calendars().first { $0.id == id }?.title
    }

    var calendarWarning: String? {
        switch gateway.access() {
        case .denied: return "Calendar access is disabled. The schedule stays in the app and is not added to your calendar. You can grant access in Settings."
        case .writeOnly: return "Calendar access is write-only, so Zeigarnik cannot find or update its events. The schedule stays in the app. You can allow full access in System Settings."
        case .notDetermined: return "You will be asked for calendar access when you save."
        case .granted: return model.settings.calendarId == nil ? "No target calendar selected. Choose one in Settings; the schedule will remain pending until then." : nil
        }
    }

    /// Asks for calendar access the first time a plan should go to Calendar, then reconciles.
    func ensureCalendarAccess() {
        guard gateway.access() == .notDetermined else { return }
        Task {
            _ = await gateway.requestAccess()
            model.reconcileCalendar()
        }
    }

    static func openNowProvider(store: Store, config: ScanConfig, runner: ProcessRunner) -> @Sendable () async -> OpenNowState {
        {
            guard FileManager.default.isExecutableFile(atPath: config.hcPath) else { return .unknown("herdr is not installed") }
            let projects = (try? store.currentProjectPaths()) ?? []
            let mapper = ProjectMapper(projects: projects, home: config.home, workspaceRoot: config.roots.first?.path ?? config.home)
            return await openNow(runner: runner, hcPath: config.hcPath, mapper: mapper)
        }
    }
}

/// Current target calendar id, readable from the calendar sync actor.
final class CalendarTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?

    init(_ value: String?) { current = value }

    var value: String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@MainActor
final class ScanRelay {
    weak var model: AppModel?
    weak var environment: AppEnvironment?

    func forward(_ report: ScanReport) {
        guard let model else { return }
        Task { await model.scanFinished() }
        environment?.refreshUpcoming()
    }
}
