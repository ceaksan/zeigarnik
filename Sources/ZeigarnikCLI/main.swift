import Foundation
import ZeigarnikAgent
import ZeigarnikCore

private let usage = """
Usage: zeigarnik [--db <path>] <command>

  projects [--query <text>] [--json]       Projects and their state.
  status <project> [--json]                One project: state, recent notes, open drafts.
  notes list [--project <p>] [--since <day>] [--until <day>] [--limit <n>] [--json]
  notes show <id> [--json]
  notes add --project <p> [--day <day>] [<text>...]   Text from the arguments, or from standard input.
  notes edit <id> [<text>...]              Replaces the text; from standard input when no text is given.
  notes delete <id>
  drafts [--project <p>] [--json]          Note drafts from project state not yet accepted or dismissed.
  mcp                                      Run as an MCP server on standard input and output.

  <project> is an id, a display name or a path; <id> is a note id or a unique prefix of 4 or more characters;
  <day> is YYYY-MM-DD. --db defaults to ~/Library/Application Support/Zeigarnik/zeigarnik.sqlite.
"""

private func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("zeigarnik: \(message)\n".utf8))
    exit(code)
}

/// Splits arguments into flags with values, boolean flags and positionals.
private struct Arguments {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var positionals: [String] = []

    init(_ arguments: [String], valued: Set<String>, boolean: Set<String>) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if valued.contains(argument) {
                guard index + 1 < arguments.count else { fail("Missing value after \(argument)\n\(usage)", code: 2) }
                values[argument] = arguments[index + 1]
                index += 2
                continue
            }
            if boolean.contains(argument) {
                flags.insert(argument)
            } else if argument.hasPrefix("--") && argument.count > 2 {
                fail("Unknown option: \(argument)\n\(usage)", code: 2)
            } else {
                positionals.append(argument)
            }
            index += 1
        }
    }
}

/// The app's README and architecture switches and activity gap, so drafts match what the app shows.
private struct AppSettingsSubset: Decodable {
    var checkReadme: Bool?
    var checkArchitecture: Bool?
    var activityGapMinutes: Int?

    static func load() -> AppSettingsSubset {
        guard let data = UserDefaults(suiteName: "com.ceaksan.zeigarnik")?.data(forKey: "zeigarnik.settings"),
              let settings = try? JSONDecoder().decode(AppSettingsSubset.self, from: data) else { return AppSettingsSubset() }
        return settings
    }
}

private func readText(_ words: [String]) -> String {
    if !words.isEmpty { return words.joined(separator: " ") }
    guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { fail("Give the note text as arguments or on standard input.", code: 2) }
    return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

private func line(_ note: NoteRecord) -> String {
    let text = note.text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    return "\(note.id.prefix(8).lowercased())  \(note.day)  \(note.project): \(text)"
}

private func run(_ service: AgentService, _ command: String, _ rest: [String]) throws {
    switch command {
    case "projects":
        let args = Arguments(rest, valued: ["--query"], boolean: ["--json"])
        let projects = try service.projects(matching: args.values["--query"])
        if args.flags.contains("--json") { return try printJSON(projects) }
        for p in projects {
            let state = p.state == .missing ? " (missing)" : ""
            print("\(p.name)\(state)  push: \(p.push)  uncommitted: \(p.uncommittedFiles.map(String.init) ?? "?")  README: \(p.readme)  notes: \(p.notes)  drafts: \(p.openDrafts)")
        }
    case "status":
        let args = Arguments(rest, valued: [], boolean: ["--json"])
        guard let ref = args.positionals.first else { fail("status needs a project.\n\(usage)", code: 2) }
        let status = try service.projectStatus(ref)
        if args.flags.contains("--json") { return try printJSON(status) }
        let p = status.project
        print("\(p.name)  \(p.path)")
        if let summary = status.summary { print(summary) }
        print("Branch: \(p.branch ?? "?")  push: \(p.push)  uncommitted: \(p.uncommittedFiles.map(String.init) ?? "?")")
        print("README: \(p.readme)  architecture: \(p.architecture)")
        if !status.drafts.isEmpty { print("\nDrafts:"); status.drafts.forEach { print("  [\($0.kind.rawValue)] \($0.text)") } }
        if !status.notes.isEmpty { print("\nNotes:"); status.notes.forEach { print("  " + line($0)) } }
    case "notes":
        guard let sub = rest.first else { fail("notes needs list, show, add, edit or delete.\n\(usage)", code: 2) }
        let tail = Array(rest.dropFirst())
        switch sub {
        case "list":
            let args = Arguments(tail, valued: ["--project", "--since", "--until", "--limit"], boolean: ["--json"])
            let limit = try args.values["--limit"].map { value -> Int in
                guard let n = Int(value), n > 0 else { throw AgentError.missingArgument("--limit as a positive number") }
                return n
            }
            let notes = try service.notes(project: args.values["--project"], since: args.values["--since"], until: args.values["--until"], limit: limit)
            if args.flags.contains("--json") { return try printJSON(notes) }
            notes.forEach { print(line($0)) }
        case "show":
            let args = Arguments(tail, valued: [], boolean: ["--json"])
            guard let id = args.positionals.first else { fail("notes show needs a note id.", code: 2) }
            let note = try service.note(id)
            if args.flags.contains("--json") { return try printJSON(note) }
            print("\(note.id)  \(note.day)  \(note.project)\n\n\(note.text)")
        case "add":
            let args = Arguments(tail, valued: ["--project", "--day"], boolean: ["--json"])
            guard let project = args.values["--project"] else { fail("notes add needs --project.", code: 2) }
            let note = try service.addNote(project: project, text: readText(args.positionals), day: args.values["--day"])
            if args.flags.contains("--json") { return try printJSON(note) }
            print("Added " + line(note))
        case "edit":
            let args = Arguments(tail, valued: [], boolean: ["--json"])
            guard let id = args.positionals.first else { fail("notes edit needs a note id.", code: 2) }
            let note = try service.updateNote(id, text: readText(Array(args.positionals.dropFirst())))
            if args.flags.contains("--json") { return try printJSON(note) }
            print("Updated " + line(note))
        case "delete":
            let args = Arguments(tail, valued: [], boolean: [])
            guard let id = args.positionals.first else { fail("notes delete needs a note id.", code: 2) }
            print("Deleted " + line(try service.deleteNote(id)))
        default:
            fail("Unknown notes command: \(sub)\n\(usage)", code: 2)
        }
    case "drafts":
        let args = Arguments(rest, valued: ["--project"], boolean: ["--json"])
        let drafts = try service.drafts(project: args.values["--project"])
        if args.flags.contains("--json") { return try printJSON(drafts) }
        drafts.forEach { print("\($0.project)  [\($0.kind.rawValue)]  \($0.text)") }
    case "mcp":
        let server = MCPServer(service: service)
        while let request = readLine(strippingNewline: true) {
            guard !request.trimmingCharacters(in: .whitespaces).isEmpty, let response = server.handle(line: request) else { continue }
            FileHandle.standardOutput.write(Data((response + "\n").utf8))
        }
    default:
        fail("Unknown command: \(command)\n\(usage)", code: 2)
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.contains("--help") || arguments.first == "help" {
    print(usage)
    exit(0)
}
if arguments.first == "--version" {
    print(zeigarnikVersion)
    exit(0)
}
var databasePath = AppPaths.databaseURL(home: FileManager.default.homeDirectoryForCurrentUser).path
if arguments.first == "--db" {
    guard arguments.count >= 2 else { fail("Missing path after --db", code: 2) }
    databasePath = (arguments[1] as NSString).expandingTildeInPath
    arguments.removeFirst(2)
}
guard let command = arguments.first else { fail(usage, code: 2) }
guard FileManager.default.fileExists(atPath: databasePath) else {
    fail("No Zeigarnik database at \(databasePath). Open the app once, or pass --db.", code: 1)
}

let store: Store
do {
    store = try Store(path: databasePath)
} catch {
    fail("Cannot open the database at \(databasePath): \(error)", code: 1)
}
private let settings = AppSettingsSubset.load()
let service = AgentService(store: store, gap: TimeInterval((settings.activityGapMinutes ?? 15) * 60),
                           checks: NoteDraftChecks(readme: settings.checkReadme ?? true, architecture: settings.checkArchitecture ?? true))
do {
    try run(service, command, Array(arguments.dropFirst()))
} catch {
    fail("\(error)", code: 1)
}
