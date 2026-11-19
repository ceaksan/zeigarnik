import Foundation

public func formatProjectTable(_ rows: [ProjectRow], errors: [ScanError], calendar: Calendar) -> String {
    let headers = ["Project", "Last activity", "Last commit", "Dirty", "Push", "README", "≈ Time", "Spec"]
    let values = rows.map { row -> [String] in
        let project = (row.pinned ? "★ " : "") + row.displayName
            + (row.state == .missing ? " (missing)" : "")
        let activity: String
        if let date = row.lastActivityAt, let agent = row.lastActivityAgent {
            activity = dayKey(date, calendar: calendar) + " " + agent.rawValue
        } else {
            activity = "-"
        }
        let commit = row.lastCommitAt.map { dayKey($0, calendar: calendar) } ?? "-"
        let dirty = row.status.map { String($0.changed + $0.untracked) } ?? "no git"
        let push: String
        if let status = row.status {
            push = status.upstream == nil ? "no upstream" : "↑\(status.ahead ?? 0) ↓\(status.behind ?? 0)"
        } else {
            push = "-"
        }
        let readme: String
        switch row.readme {
        case .current: readme = "ok"
        case .noReadme: readme = "none"
        case .behind(let commits, _, let manifestChanged):
            readme = "behind \(commits)" + (manifestChanged ? " (manifest)" : "")
        case nil: readme = "-"
        }
        let time = row.totalSeconds == 0 ? "-"
            : String(format: "≈%.1fh", locale: Locale(identifier: "en_US_POSIX"), row.totalSeconds / 3600)
        return [project, activity, commit, dirty, push, readme, time, formatSpecHeadline(row.spec)]
    }

    let table = [headers] + values
    var widths = headers.map(\.count)
    for cells in values {
        for index in headers.indices {
            widths[index] = max(widths[index], cells[index].count)
        }
    }
    var lines = table.map { cells in
        cells.enumerated().map { index, cell in
            index == headers.count - 1 ? cell : cell + String(repeating: " ", count: widths[index] - cell.count)
        }.joined(separator: "  ")
    }
    if !errors.isEmpty {
        lines.append("")
        lines.append("Errors:")
        lines.append(contentsOf: errors.map { "\($0.projectPath ?? "-") : \($0.message)" })
    }
    return lines.joined(separator: "\n")
}

private func formatSpecHeadline(_ headline: SpecHeadline?) -> String {
    if let current = headline?.current {
        let title = formatSpecTitle(current.title)
        switch current.stage {
        case .design: return "Design: " + title
        case .inProgress(let done, let total, let external):
            return "\(done)/\(total)" + (external > 0 ? " (\(external) ext)" : "") + ": " + title
        case .declaredDone(let done, let total): return "declared done \(done)/\(total): " + title
        case .done: return "Done: " + title
        }
    }
    if let lastDone = headline?.lastDone {
        return "Done: " + formatSpecTitle(lastDone.title)
    }
    return "-"
}

private func formatSpecTitle(_ title: String) -> String {
    title.count > 40 ? String(title.prefix(40)) + "…" : title
}
