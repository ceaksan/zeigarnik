import Foundation

public enum AppAppearance: String, Sendable, Codable, CaseIterable {
    case system, light, dark
}

public struct AppSettings: Sendable, Equatable, Codable {
    public var roots: [String]
    public var vaultRoot: String?
    public var calendarId: String?
    public var launchAtLogin: Bool
    /// Bundle ids; nil means the first installed `OpenTarget`.
    public var terminalApp: String?
    public var editorApp: String?
    public var appearance: AppAppearance
    public var welcomeShown: Bool
    public var checkReadme: Bool
    public var checkArchitecture: Bool
    /// Asks GitHub or GitLab whether each repository is public: daily after a clear answer, each scan while unknown.
    public var checkVisibility: Bool
    /// Hours between automatic scans; one of `scanIntervalChoices`.
    public var scanIntervalHours: Int
    /// Messages further apart than this many minutes do not count as one stretch of work; one of `activityGapChoices`.
    public var activityGapMinutes: Int

    public static let scanIntervalChoices = [1, 2, 4, 8]
    public static let activityGapChoices = [5, 10, 15, 20, 30]

    public var scanInterval: Duration { .seconds(scanIntervalHours * 3600) }
    public var activityGap: TimeInterval { TimeInterval(activityGapMinutes * 60) }

    public init(roots: [String], vaultRoot: String?, calendarId: String?, launchAtLogin: Bool,
                terminalApp: String? = nil, editorApp: String? = nil, appearance: AppAppearance = .system,
                welcomeShown: Bool = false, checkReadme: Bool = true, checkArchitecture: Bool = true, checkVisibility: Bool = true,
                scanIntervalHours: Int = 2, activityGapMinutes: Int = 15) {
        self.scanIntervalHours = scanIntervalHours
        self.activityGapMinutes = activityGapMinutes
        self.checkVisibility = checkVisibility
        self.welcomeShown = welcomeShown
        self.checkReadme = checkReadme
        self.checkArchitecture = checkArchitecture
        self.roots = roots
        self.vaultRoot = vaultRoot
        self.calendarId = calendarId
        self.launchAtLogin = launchAtLogin
        self.terminalApp = terminalApp
        self.editorApp = editorApp
        self.appearance = appearance
    }

    /// Fields added after the first release decode with defaults, so saved settings survive updates.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(roots: try c.decode([String].self, forKey: .roots),
                  vaultRoot: try c.decodeIfPresent(String.self, forKey: .vaultRoot),
                  calendarId: try c.decodeIfPresent(String.self, forKey: .calendarId),
                  launchAtLogin: try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
                  terminalApp: try c.decodeIfPresent(String.self, forKey: .terminalApp),
                  editorApp: try c.decodeIfPresent(String.self, forKey: .editorApp),
                  appearance: try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system,
                  welcomeShown: try c.decodeIfPresent(Bool.self, forKey: .welcomeShown) ?? false,
                  checkReadme: try c.decodeIfPresent(Bool.self, forKey: .checkReadme) ?? true,
                  checkArchitecture: try c.decodeIfPresent(Bool.self, forKey: .checkArchitecture) ?? true,
                  checkVisibility: try c.decodeIfPresent(Bool.self, forKey: .checkVisibility) ?? true,
                  scanIntervalHours: Self.choice(try c.decodeIfPresent(Int.self, forKey: .scanIntervalHours), in: Self.scanIntervalChoices, default: 2),
                  activityGapMinutes: Self.choice(try c.decodeIfPresent(Int.self, forKey: .activityGapMinutes), in: Self.activityGapChoices, default: 15))
    }

    private static func choice(_ value: Int?, in choices: [Int], default fallback: Int) -> Int {
        value.flatMap { choices.contains($0) ? $0 : nil } ?? fallback
    }

    /// A fresh install starts with nothing chosen; the welcome screen and Settings ask for folders.
    public static func firstRun(home: URL, fileManager: FileManager) -> AppSettings {
        AppSettings(roots: [], vaultRoot: nil, calendarId: nil, launchAtLogin: false)
    }
}

public struct SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "zeigarnik.settings"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load(home: URL) -> AppSettings {
        if let data = defaults.data(forKey: Self.key), let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return .firstRun(home: home, fileManager: .default)
    }

    public func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
    }
}

public func scanConfig(from settings: AppSettings, home: URL,
                       isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> ScanConfig {
    var config = ScanConfig.standard(roots: settings.roots.map { URL(fileURLWithPath: $0) }, vaultRoot: settings.vaultRoot.map { URL(fileURLWithPath: $0) }, home: home)
    config.hcPath = hcPath(home: home, isExecutable: isExecutable)
    config.checkVisibility = settings.checkVisibility
    config.gap = settings.activityGap
    config.markRemovedRoots = true
    return config
}

/// What a settings change requires: a rescan (roots or vault changed), a fetch (a root was added), a calendar reconcile, a login item update,
/// a reload (the activity gap changed; totals are computed when rows load), a new timer interval.
public struct SettingsEffects: Equatable, Sendable {
    public var rescan: Bool
    public var fetch: Bool
    public var calendarChanged: Bool
    public var loginChanged: Bool
    public var reload: Bool
    public var intervalChanged: Bool
    public var visibilityChanged: Bool
    /// The running scanner carries a copy of the settings; any change it reads needs a new scanner, even without a rescan.
    public var rebuildScanner: Bool { rescan || visibilityChanged }

    public init(rescan: Bool, fetch: Bool, calendarChanged: Bool, loginChanged: Bool, reload: Bool = false, intervalChanged: Bool = false,
                visibilityChanged: Bool = false) {
        self.visibilityChanged = visibilityChanged
        self.rescan = rescan
        self.fetch = fetch
        self.calendarChanged = calendarChanged
        self.loginChanged = loginChanged
        self.reload = reload
        self.intervalChanged = intervalChanged
    }

    public init(from old: AppSettings, to new: AppSettings) {
        let added = !Set(new.roots).isSubset(of: Set(old.roots))
        self.init(rescan: old.roots != new.roots || old.vaultRoot != new.vaultRoot || (new.checkVisibility && !old.checkVisibility), fetch: added,
                  calendarChanged: old.calendarId != new.calendarId, loginChanged: old.launchAtLogin != new.launchAtLogin,
                  reload: old.activityGapMinutes != new.activityGapMinutes, intervalChanged: old.scanIntervalHours != new.scanIntervalHours,
                  visibilityChanged: old.checkVisibility != new.checkVisibility)
    }
}

/// herdr's `hc`. Apps launched from Finder get a minimal PATH, so the usual install folders are checked by name.
public func hcPath(home: URL, isExecutable: (String) -> Bool) -> String {
    let userBin = home.appendingPathComponent(".local/bin/hc").path
    return [userBin, "/opt/homebrew/bin/hc", "/usr/local/bin/hc"].first(where: isExecutable) ?? userBin
}
