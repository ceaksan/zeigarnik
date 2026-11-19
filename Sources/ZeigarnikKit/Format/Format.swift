import Foundation

/// Display text. Words are English; dates, times and decimals follow the calendar's (or given) locale.
public enum Format {
    public static func relativeDay(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "-" }
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) { return dayMonth(date, calendar: calendar) }
        return formatter(shortDatePattern(calendar.locale), calendar).string(from: date)
    }

    public static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        formatter(dayMonthPattern(calendar.locale), calendar).string(from: date)
    }

    /// For `yyyy-MM-dd` day keys; anything else is returned as is.
    public static func dayMonth(day: String, calendar: Calendar) -> String {
        guard let date = date(of: day, calendar: calendar) else { return day }
        return dayMonth(date, calendar: calendar)
    }

    public static func time(_ date: Date, calendar: Calendar) -> String {
        let f = formatter(nil, calendar)
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    public static func dayMonthTime(_ date: Date, calendar: Calendar) -> String {
        dayMonth(date, calendar: calendar) + " " + time(date, calendar: calendar)
    }

    public static func duration(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        guard seconds > 0 else { return "≈0 min" }
        let minutes = max(5, Int((seconds / 300).rounded()) * 5)
        if minutes < 60 { return "≈\(minutes) min" }
        let hours = seconds / 3600
        if hours >= 10 { return "≈\(Int(hours.rounded())) h" }
        let tenths = (hours * 10).rounded() / 10
        return "≈" + tenths.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale)) + " h"
    }

    public static func visibility(_ value: RepoVisibility?) -> String { value?.rawValue ?? "-" }

    public static func dirty(_ status: GitStatus?) -> String {
        status.map { "\($0.changed + $0.untracked)" } ?? "?"
    }

    public static func push(_ status: GitStatus?) -> String {
        guard let status else { return "?" }
        guard status.branch != nil else { return "detached" }
        guard status.upstream != nil else { return "no upstream" }
        let parts = [(status.ahead ?? 0) > 0 ? "↑\(status.ahead!)" : nil, (status.behind ?? 0) > 0 ? "↓\(status.behind!)" : nil].compactMap { $0 }
        return parts.isEmpty ? "0" : parts.joined(separator: " ")
    }

    public static func pushNeedsAttention(_ status: GitStatus?) -> Bool {
        guard let status, status.branch != nil else { return false }
        return status.upstream == nil || (status.ahead ?? 0) > 0 || (status.behind ?? 0) > 0
    }

    public static func readme(_ drift: ReadmeDrift?) -> String {
        switch drift {
        case nil: "unknown"
        case .noReadme?: "none"
        case .current?: "up to date"
        case .behind(let commits, _, let manifest)?: "\(commits) \(commits == 1 ? "commit" : "commits") behind" + (manifest ? ", manifest changed" : "")
        }
    }

    /// Table cell form; the full `readme(_:)` text goes in the help tooltip.
    public static func readmeShort(_ drift: ReadmeDrift?) -> String {
        if case .behind(let commits, _, _)? = drift { return "\(commits) behind" }
        return drift == nil ? "?" : readme(drift)
    }

    public static func architecture(_ doc: ArchitectureDoc?, calendar: Calendar) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        func head(_ path: String, _ updatedAt: Date?, _ since: Int) -> String {
            guard let updatedAt else { return "\(path) · not committed yet" }
            return "\(path) · updated \(dayMonth(updatedAt, calendar: calendar)) · \(plural(since, "commit")) since"
        }
        switch doc {
        case nil: return "unknown"
        case .none?: return "none"
        case .current(let path, let updatedAt, let since)?: return head(path, updatedAt, since)
        case .behind(let path, let updatedAt, let since, let dirs, let files, let manifest)?:
            let reasons = [dirs.isEmpty ? nil : plural(dirs.count, "new folder"), files == 0 ? nil : plural(files, "new file"),
                           manifest ? "manifest changed" : nil].compactMap { $0 }
            return head(path, updatedAt, since) + " · " + reasons.joined(separator: ", ")
        }
    }

    public static func specShort(_ headline: SpecHeadline?) -> String {
        guard let headline else { return "-" }
        guard let current = headline.current else { return headline.lastDone == nil ? "-" : "Last spec done" }
        return stage(current.stage)
    }

    public static func specLine(_ spec: SpecSummary) -> String {
        "Spec: \(spec.declared ?? "not declared") · Evidence: \(stage(spec.stage))"
    }

    static func stage(_ stage: SpecStage) -> String {
        switch stage {
        case .design: return "Design"
        case .done: return "Done"
        case .declaredDone(let done, let total): return "declared done, evidence \(done)/\(total)"
        case .inProgress(let done, let total, let external):
            guard total > 0 else { return "no evidence" }
            return "\(done)/\(total)" + (external > 0 ? ", \(external) external" : "")
        }
    }

    public static func dayTitle(_ day: String, calendar: Calendar) -> String {
        guard let date = date(of: day, calendar: calendar) else { return day }
        return date.formatted(style(calendar).day().month(.wide).year())
    }

    public static func monthTitle(year: Int, month: Int, calendar: Calendar) -> String {
        guard (1...12).contains(month), let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) else { return "\(year)" }
        return date.formatted(style(calendar).month(.wide).year())
    }

    // MARK: Helpers

    static func date(of day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .autoupdatingCurrent, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// Table cells format every row on each render; building a DateFormatter per call made sidebar selection visibly slow.
    static func formatter(_ pattern: String?, _ calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? .autoupdatingCurrent
        let key = [pattern ?? "", locale.identifier, calendar.timeZone.identifier, "\(calendar.identifier)", "\(calendar.firstWeekday)"].joined(separator: "|")
        return formatterCache.value(key) {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = locale
            if let pattern { f.dateFormat = pattern }
            return f
        }
    }

    private static func shortDatePattern(_ locale: Locale?) -> String {
        let locale = locale ?? .autoupdatingCurrent
        return patternCache.value(locale.identifier) {
            let f = DateFormatter()
            f.locale = locale
            f.dateStyle = .short
            f.timeStyle = .none
            return f.dateFormat ?? "d.MM.y"
        }
    }

    private static let formatterCache = LockedCache<DateFormatter>()
    private static let patternCache = LockedCache<String>()

    /// The locale's short date pattern without its year: en_GB "dd/MM/y" gives "dd/MM", en_US "M/d/yy" gives "M/d".
    static func dayMonthPattern(_ locale: Locale?) -> String {
        let pattern = shortDatePattern(locale)
        for regex in [#"^y+[^dMy]*"#, #"[^dMy]*y+$"#] {
            if let range = pattern.range(of: regex, options: .regularExpression) { return pattern.replacingCharacters(in: range, with: "") }
        }
        return pattern.replacingOccurrences(of: "y", with: "")
    }
}

/// Short weekday names in grid order, starting at the calendar's first weekday.
public func weekdayHeaders(calendar: Calendar) -> [String] {
    let symbols = DateFormatter()
    symbols.locale = calendar.locale ?? .autoupdatingCurrent
    let names = symbols.shortStandaloneWeekdaySymbols ?? calendar.shortWeekdaySymbols
    let start = calendar.firstWeekday - 1
    return Array(names[start...] + names[..<start])
}

/// DateFormatter is thread-safe for formatting; the lock guards only the dictionary.
final class LockedCache<Value>: @unchecked Sendable {
    private var values: [String: Value] = [:]
    private let lock = NSLock()

    func value(_ key: String, make: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let cached = values[key] { return cached }
        let value = make()
        values[key] = value
        return value
    }
}
