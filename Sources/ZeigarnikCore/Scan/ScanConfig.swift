import Foundation

public struct ScanConfig: Sendable {
    public var roots: [URL]
    public var projectTableFile: URL
    public var vaultRoot: URL
    public var claudeHome: URL
    public var codexHome: URL
    public var hcPath: String
    public var home: String
    public var fetchConcurrency: Int = 6
    public var gap: TimeInterval = 900
    public var ingestBatchBytes: Int = 16 << 20
    public var checkVisibility = false
    /// Projects outside every root become missing. Only the app sets it: the CLI may scan a subset of the shared database.
    public var markRemovedRoots = false
    public var visibilityMaxAge: TimeInterval = 86_400
    public var visibilityConcurrency = 4

    public init(roots: [URL], projectTableFile: URL, vaultRoot: URL, claudeHome: URL, codexHome: URL, hcPath: String, home: String) {
        self.roots = roots
        self.projectTableFile = projectTableFile
        self.vaultRoot = vaultRoot
        self.claudeHome = claudeHome
        self.codexHome = codexHome
        self.hcPath = hcPath
        self.home = home
    }

    /// Tool folders under `home`; the optional project table is `CLAUDE.md` in the first root.
    public static func standard(roots: [URL], vaultRoot: URL?, home: URL) -> ScanConfig {
        ScanConfig(
            roots: roots,
            projectTableFile: roots.first?.appendingPathComponent("CLAUDE.md") ?? home.appendingPathComponent(".zeigarnik-no-table/CLAUDE.md"),
            vaultRoot: vaultRoot ?? home.appendingPathComponent(".zeigarnik-no-vault"),
            claudeHome: home.appendingPathComponent(".claude"),
            codexHome: home.appendingPathComponent(".codex"),
            hcPath: home.appendingPathComponent(".local/bin/hc").path,
            home: home.path
        )
    }
}
