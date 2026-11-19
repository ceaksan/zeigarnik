import Foundation

public enum ProjectSortKey: String, Sendable {
    case name, lastActivity, lastCommit, dirty, push, readme, time, spec, visibility
}

/// Rows without a value for the key always go last, whichever the direction; ties fall back to the name.
public func sorted(_ rows: [ProjectRow], by key: ProjectSortKey, ascending: Bool) -> [ProjectRow] {
    func name(_ a: ProjectRow, _ b: ProjectRow) -> Bool {
        a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
    }
    if key == .name {
        return rows.sorted { ascending ? name($0, $1) : name($1, $0) }
    }
    return rows.sorted { a, b in
        switch (sortValue(a, key), sortValue(b, key)) {
        case (nil, nil): return name(a, b)
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x == y ? name(a, b) : (ascending ? x < y : x > y)
        }
    }
}

private func sortValue(_ row: ProjectRow, _ key: ProjectSortKey) -> Double? {
    switch key {
    case .name: return nil
    case .lastActivity: return row.lastActivityAt?.timeIntervalSince1970
    case .lastCommit: return row.lastCommitAt?.timeIntervalSince1970
    case .dirty: return row.status.map { Double($0.changed + $0.untracked) }
    case .push:
        guard let status = row.status, status.branch != nil else { return nil }
        if status.upstream == nil { return .infinity }
        return Double((status.ahead ?? 0) + (status.behind ?? 0))
    case .readme:
        switch row.readme {
        case nil: return nil
        case .noReadme?: return -1
        case .current?: return 0
        case .behind(let commits, _, _)?: return Double(commits)
        }
    case .time: return row.totalSeconds
    case .visibility:
        switch row.visibility {
        case .private?: return 0
        case .public?: return 1
        case .unknown?, nil: return nil
        }
    case .spec:
        guard let stage = row.spec?.current?.stage else { return row.spec?.lastDone == nil ? nil : 1 }
        switch stage {
        case .design: return 0
        case .inProgress(let done, let total, _): return total > 0 ? Double(done) / Double(total) : 0
        case .declaredDone(let done, let total): return total > 0 ? Double(done) / Double(total) : 0
        case .done: return 1
        }
    }
}
