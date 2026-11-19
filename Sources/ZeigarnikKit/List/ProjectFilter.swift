import Foundation

public enum ProjectFilter: Hashable, Sendable {
    case pinned, all, openNow, uncommitted, pushOrUpstream, readmeDrift, architectureDrift, publicRepo, quiet, folder(String), missing
}

public struct FilterContext: Sendable {
    public let now: Date
    public let openNow: OpenNowState?
    public let roots: [String]

    public init(now: Date, openNow: OpenNowState?, roots: [String]) {
        self.now = now
        self.openNow = openNow
        self.roots = roots
    }
}

public let quietInterval: TimeInterval = 30 * 86_400

public enum FolderLabel {
    public static let root = "Root"
    public static let outside = "Outside"
}

public func folder(of row: ProjectRow, roots: [String]) -> String {
    for root in roots {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard row.path.hasPrefix(prefix) else { continue }
        let components = row.path.dropFirst(prefix.count).split(separator: "/")
        if components.count > 1, let first = components.first, first.range(of: #"^\d\d_"#, options: .regularExpression) != nil {
            return String(first)
        }
        return FolderLabel.root
    }
    return FolderLabel.outside
}

public func matches(_ row: ProjectRow, _ filter: ProjectFilter, _ ctx: FilterContext) -> Bool {
    let active = row.state == .active
    switch filter {
    case .pinned: return row.pinned
    case .missing: return row.state == .missing
    case .all: return active
    case .folder(let name): return active && folder(of: row, roots: ctx.roots) == name
    case .openNow:
        guard active, case .known(let owners) = ctx.openNow else { return false }
        return owners.contains(.project(row.id))
    case .uncommitted:
        guard active, let status = row.status else { return false }
        return status.changed + status.untracked > 0
    case .pushOrUpstream: return active && Format.pushNeedsAttention(row.status)
    case .architectureDrift:
        if case .behind? = row.architecture { return active }
        return false
    case .readmeDrift:
        guard active, case .behind = row.readme else { return false }
        return true
    case .publicRepo: return active && row.visibility == .public
    case .quiet:
        guard active else { return false }
        let latest = [row.lastActivityAt, row.lastCommitAt].compactMap { $0 }.max()
        return latest.map { ctx.now.timeIntervalSince($0) > quietInterval } ?? true
    }
}

public func filterCounts(_ rows: [ProjectRow], _ ctx: FilterContext) -> [ProjectFilter: Int] {
    var filters: [ProjectFilter] = [.pinned, .all, .uncommitted, .pushOrUpstream, .readmeDrift, .architectureDrift, .publicRepo, .quiet, .missing]
    if case .known = ctx.openNow { filters.append(.openNow) }
    filters += Set(rows.filter { $0.state == .active }.map { folder(of: $0, roots: ctx.roots) }).map { .folder($0) }
    var counts: [ProjectFilter: Int] = [:]
    for filter in filters { counts[filter] = rows.filter { matches($0, filter, ctx) }.count }
    return counts
}

public func search(_ rows: [ProjectRow], _ query: String) -> [ProjectRow] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return rows }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    let folded = foldTurkishI(needle)
    return rows.filter {
        foldTurkishI($0.displayName).range(of: folded, options: options) != nil
            || foldTurkishI($0.path).range(of: folded, options: options) != nil
    }
}

/// A fixed Turkish locale broke "inspect" against "Inspect" (I lowercases to ı); no locale missed "isik" against "Işık".
/// Folding ı and İ to plain i and I, then matching without a locale, finds both.
private func foldTurkishI(_ text: String) -> String {
    text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "I")
}
