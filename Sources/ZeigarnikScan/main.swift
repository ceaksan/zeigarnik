import Foundation
import ZeigarnikCore

private let usage = """
Usage: zeigarnik-scan --root <path> [--root <path>...] [--vault <path>] [--no-fetch] [--json] [--db <path>] [--help]

  --no-fetch     Skip fetching remotes.
  --json         Print the scan report and project rows as JSON.
  --db <path>    SQLite database path. Default:
                 ~/Library/Application Support/Zeigarnik/zeigarnik.sqlite
  --root <path>  Folder to scan for git repositories; repeat for several. Required.
  --vault <path> Obsidian vault for Active Tasks counts. Optional.
  --help         Show this help.
"""

private enum ArgumentError: Error, CustomStringConvertible {
    case unknown(String)
    case missingValue(String)

    var description: String {
        switch self {
        case .unknown(let argument): "Unknown argument: \(argument)"
        case .missingValue(let flag): "Missing path after \(flag)"
        }
    }
}

private struct Options {
    var noFetch = false
    var json = false
    var databasePath = AppPaths.databaseURL(home: FileManager.default.homeDirectoryForCurrentUser).path
    var roots: [URL] = []
    var vault: URL?

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--no-fetch": noFetch = true
            case "--json": json = true
            case "--db", "--root", "--vault":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw ArgumentError.missingValue(argument)
                }
                index += 1
                let path = (arguments[index] as NSString).expandingTildeInPath
                if argument == "--db" {
                    databasePath = path
                } else if argument == "--vault" {
                    vault = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
                } else {
                    roots.append(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
                }
            default: throw ArgumentError.unknown(argument)
            }
            index += 1
        }
    }
}

private struct ScanOutput: Encodable {
    let report: ScanReport
    let projects: [ProjectRow]
}

private func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("zeigarnik-scan: \(message)\n".utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print(usage)
    exit(0)
}

private let options: Options
do {
    options = try Options(arguments: arguments)
} catch {
    fail("\(error)\n\(usage)", code: 2)
}
if options.roots.isEmpty { fail("--root is required.\n\(usage)", code: 2) }

let store: Store
do {
    if options.databasePath != ":memory:" {
        let directory = URL(fileURLWithPath: options.databasePath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    store = try Store(path: options.databasePath)
} catch {
    fail("Cannot open store at \(options.databasePath): \(error)", code: 1)
}

let config = ScanConfig.standard(roots: options.roots, vaultRoot: options.vault, home: FileManager.default.homeDirectoryForCurrentUser)
let scanner = ProjectScanner(config: config, store: store, runner: ProcessRunner())
let report = await scanner.scan(fetch: !options.noFetch)
do {
    let rows = try store.projectRows(today: dayKey(Date(), calendar: .current), gap: config.gap)
    if options.json {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ScanOutput(report: report, projects: rows))
        print(String(decoding: data, as: UTF8.self))
    } else {
        print(formatProjectTable(rows, errors: report.errors, calendar: .current))
    }
} catch {
    fail("Cannot produce scan output: \(error)", code: 2)
}
