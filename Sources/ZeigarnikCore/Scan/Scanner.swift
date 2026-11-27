import Foundation

public struct ScanError: Sendable, Equatable, Codable {
    public let projectPath: String?
    public let message: String

    public init(projectPath: String?, message: String) {
        self.projectPath = projectPath
        self.message = message
    }
}

public struct ProjectRelink: Sendable, Equatable, Codable {
    public let projectId: String
    public let fromPath: String
    public let toPath: String

    public init(projectId: String, fromPath: String, toPath: String) {
        self.projectId = projectId
        self.fromPath = fromPath
        self.toPath = toPath
    }
}

public struct ScanReport: Sendable, Codable {
    public let startedAt: Date
    public let finishedAt: Date
    public let projects: Int
    public let errors: [ScanError]
    public let openNow: OpenNowState
    public let relinks: [ProjectRelink]

    public init(startedAt: Date, finishedAt: Date, projects: Int, errors: [ScanError], openNow: OpenNowState, relinks: [ProjectRelink] = []) {
        self.relinks = relinks
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.projects = projects
        self.errors = errors
        self.openNow = openNow
    }
}

public actor ProjectScanner {
    let config: ScanConfig
    let store: Store
    let runner: CommandRunning
    let visibilityProbe: (any VisibilityProbing)?
    let log: ScanLog

    public init(config: ScanConfig, store: Store, runner: CommandRunning, visibilityProbe: (any VisibilityProbing)? = nil, log: ScanLog = ScanLog()) {
        self.config = config
        self.store = store
        self.runner = runner
        self.visibilityProbe = visibilityProbe
        self.log = log
    }

    struct Unit: Sendable {
        var main: URL
        var checkouts: [URL]
        var identity: GitIdentity?
    }

    struct Work: Sendable {
        let projectId: String
        let unit: Unit
        let vaultDirectory: String?
        let overrides: [String: OwnerSpecOverride]
    }

    struct WorkResult: Sendable {
        let snapshot: ProjectSnapshot
        let summary: String?
        /// nil when history could not be read: keep the stored days.
        let commitDays: [String: Int]?
        /// nil when evidence inputs could not be read: keep the stored evidence.
        let specs: [SpecSummary]?
        let errors: [ScanError]
    }

    public func scan(fetch: Bool) async -> ScanReport {
        let started = Date()
        var errors: [ScanError] = []
        var relinks: [ProjectRelink] = []
        let fm = FileManager.default
        let inspector = GitInspector(runner: runner)
        let calendar = Calendar.current
        let today = dayKey(started, calendar: calendar)

        // 1. Project table.
        var tableRows: [ProjectTableRow] = []
        var tableReadable = true
        do {
            if FileManager.default.fileExists(atPath: config.projectTableFile.path) {
                tableRows = parseProjectTable(try String(contentsOf: config.projectTableFile, encoding: .utf8))
            }
        } catch {
            tableReadable = false
            errors.append(ScanError(projectPath: config.projectTableFile.path, message: "Cannot read project table: \(error.localizedDescription)"))
        }
        let tableBase = config.projectTableFile.deletingLastPathComponent()
        let tableEntries: [(row: ProjectTableRow, url: URL)] = tableRows.compactMap { row in
            row.directory.map { (row, tableBase.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL) }
        }

        // 2. Discovery: roots, then table directories outside them.
        let discovery = discoverRepositories(roots: config.roots)
        errors += discovery.errors.map { ScanError(projectPath: nil, message: $0) }
        var candidates = discovery.repos
        var nonGit: [URL] = []
        for entry in tableEntries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.url.path, isDirectory: &isDir), isDir.boolValue,
                  !candidates.contains(where: { isInside(entry.url, $0) }) else { continue }
            if fm.fileExists(atPath: entry.url.appendingPathComponent(".git").path) {
                candidates.append(entry.url)
            } else {
                nonGit.append(entry.url)
            }
        }

        // Group checkouts by common git directory.
        var units: [String: Unit] = [:]
        var order: [String] = []
        for repo in candidates {
            let identity = await inspector.identity(repo)
            var checkouts = [repo]
            switch await inspector.worktrees(repo) {
            case .success(let list):
                checkouts = list.filter { fm.fileExists(atPath: $0.path) }
                if !checkouts.contains(repo) { checkouts.append(repo) }
            case .failure(let error):
                errors.append(ScanError(projectPath: repo.path, message: "\(error.command): \(error.message)"))
            }
            if var existing = units[identity.commonDir] {
                for checkout in checkouts where !existing.checkouts.contains(checkout) { existing.checkouts.append(checkout) }
                units[identity.commonDir] = existing
            } else {
                units[identity.commonDir] = Unit(main: checkouts.first ?? repo, checkouts: checkouts, identity: identity)
                order.append(identity.commonDir)
            }
        }
        nonGit.removeAll { url in units.values.contains { $0.checkouts.contains { isInside(url, $0) } } }

        func tableRow(for unit: Unit) -> ProjectTableRow? {
            tableEntries.first { entry in unit.checkouts.contains(entry.url) || entry.url == unit.main }?.row
        }

        // 3. Identity.
        var known: [KnownProject] = []
        do { known = try store.knownProjects() } catch { errors.append(ScanError(projectPath: nil, message: "Store: \(error)")) }
        var works: [Work] = []
        var mapperEntries: [(id: String, path: String)] = []
        var seen = Set<String>()
        let allUnits = order.compactMap { units[$0] } + nonGit.map { Unit(main: $0, checkouts: [$0], identity: nil) }
        var resolutions = allUnits.map { unit in
            resolveIdentity(path: unit.main.path, identity: unit.identity, known: known, pathExists: { FileManager.default.fileExists(atPath: $0) })
        }
        var relinkClaims: [String: Int] = [:]
        for resolution in resolutions { if case .relinked(let id, _) = resolution { relinkClaims[id, default: 0] += 1 } }
        for index in resolutions.indices {
            if case .relinked(let id, _) = resolutions[index], relinkClaims[id, default: 0] > 1 { resolutions[index] = .ambiguous([id]) }
        }
        for (unit, resolution) in zip(allUnits, resolutions) {
            let row = tableRow(for: unit)
            let name = row?.name ?? unit.main.lastPathComponent
            if case .ambiguous(let ids) = resolution {
                errors.append(ScanError(projectPath: unit.main.path, message: "Ambiguous re-link candidates \(ids.joined(separator: ", ")); created a new project"))
            }
            do {
                let id = try store.upsertProject(resolution: resolution, path: unit.main.path, displayName: name, identity: unit.identity)
                if case .relinked(_, let fromPath) = resolution {
                    relinks.append(ProjectRelink(projectId: id, fromPath: fromPath, toPath: unit.main.path))
                }
                seen.insert(id)
                for checkout in unit.checkouts { mapperEntries.append((id: id, path: checkout.path)) }
                try store.recordPaths(projectId: id, unit.checkouts.map(\.path))
                works.append(Work(projectId: id, unit: unit, vaultDirectory: row?.vaultDirectory, overrides: (try? store.specOverrides(projectId: id)) ?? [:]))
            } catch {
                errors.append(ScanError(projectPath: unit.main.path, message: "Store: \(error)"))
            }
        }
        do {
            if tableReadable {
                let listedPaths = Set(tableEntries.map { $0.url.path })
                let tableIds = Set(try store.projectPaths().filter { listedPaths.contains($0.path) }.map(\.id))
                try store.updateTableMembership(projectIds: tableIds, tablePath: config.projectTableFile.resolvingSymlinksInPath().standardizedFileURL.path)
                let completeRoots = discovery.enumeratedRoots.subtracting(discovery.incompleteRoots)
                try store.markMissing(exceptIds: seen, underRoots: completeRoots.map(\.path), currentRoots: config.markRemovedRoots ? config.roots.map(\.path) : nil)
            }
        } catch {
            errors.append(ScanError(projectPath: nil, message: "Store: \(error)"))
        }

        // 4. Per-project facts, bounded concurrency.
        if works.contains(where: { $0.vaultDirectory != nil }), !fm.isReadableFile(atPath: config.vaultRoot.path) {
            errors.append(ScanError(projectPath: config.vaultRoot.path, message: "Cannot read vault"))
        }
        let vaultRoot = config.vaultRoot
        await withTaskGroup(of: WorkResult.self) { group in
            var pending = works.makeIterator()
            for _ in 0..<min(max(1, config.fetchConcurrency), works.count) {
                guard let work = pending.next() else { break }
                group.addTask { await Self.inspect(work, inspector: inspector, fetch: fetch, vaultRoot: vaultRoot, calendar: calendar, today: today) }
            }
            while let result = await group.next() {
                if let work = pending.next() {
                    group.addTask { await Self.inspect(work, inspector: inspector, fetch: fetch, vaultRoot: vaultRoot, calendar: calendar, today: today) }
                }
                errors += result.errors
                do {
                    try store.writeSnapshot(result.snapshot)
                    try store.updateSummary(projectId: result.snapshot.projectId, result.summary)
                    if let days = result.commitDays { try store.replaceCommitDays(projectId: result.snapshot.projectId, days) }
                    if let specs = result.specs { try store.replaceSpecEvidence(projectId: result.snapshot.projectId, specs) }
                } catch {
                    errors.append(ScanError(projectPath: nil, message: "Store: \(error)"))
                }
            }
        }

        // 5. Activity.
        ingestClaude(&errors)
        ingestCodex(&errors)
        let currentPaths = Set(mapperEntries.map(\.path))
        let pastEntries = ((try? store.projectPaths()) ?? []).filter { !currentPaths.contains($0.path) }
        let mapper = ProjectMapper(projects: mapperEntries + pastEntries, home: config.home, workspaceRoot: config.roots.first?.path ?? config.home)
        do { try store.reassignOwners(mapper: mapper) } catch { errors.append(ScanError(projectPath: nil, message: "Store: \(error)")) }

        // 6. Open now.
        let open = await openNow(runner: runner, hcPath: config.hcPath, mapper: mapper)

        // 7. Repository visibility, at most once a day per project; unknown answers are asked again next scan.
        if config.checkVisibility, let probe = visibilityProbe {
            await updateVisibility(works, probe: probe, now: started, errors: &errors)
        }

        let report = ScanReport(startedAt: started, finishedAt: Date(), projects: seen.count, errors: errors, openNow: open, relinks: relinks)
        log.record(report)
        return report
    }

    static func inspect(_ work: Work, inspector: GitInspector, fetch: Bool, vaultRoot: URL, calendar: Calendar, today: String) async -> WorkResult {
        let fm = FileManager.default
        let main = work.unit.main
        var errors: [ScanError] = []
        func note(_ message: String) { errors.append(ScanError(projectPath: main.path, message: message)) }

        var status: GitStatus?
        var fetchOutcome: FetchOutcome?
        var history: [CommitRecord] = []
        var tracked: Set<String> = []
        var historyFailed = false
        var trackedFailed = false
        if let identity = work.unit.identity {
            if fetch {
                fetchOutcome = await inspector.fetch(main)
                if case .failed(let message) = fetchOutcome { note(formatFetchFailure(message)) }
                if case .timedOut = fetchOutcome { note("fetch: timed out") }
            }
            do {
                let mainStatus = try await inspector.status(main)
                var others: [GitStatus] = []
                for checkout in work.unit.checkouts where checkout != main {
                    do { others.append(try await inspector.status(checkout)) } catch { note("status \(checkout.path): \(error)") }
                }
                status = aggregateStatus(main: mainStatus, others: others)
            } catch {
                note("status: \(error)")
            }
            if !identity.rootCommits.isEmpty {
                do { history = try await inspector.history(main) } catch { historyFailed = true; note("history: \(error)") }
            }
            do { tracked = try await inspector.trackedFiles(main) } catch { trackedFailed = true; note("ls-files: \(error)") }
        }

        let readmePath = findReadme(in: tracked) ?? ["README.md", "readme.md", "README"].first { fm.fileExists(atPath: main.appendingPathComponent($0).path) }
        let readme: ReadmeDrift?
        if work.unit.identity == nil {
            readme = readmePath == nil ? .noReadme : .current
        } else {
            readme = historyFailed ? nil : await inspector.readmeState(main, history: history, readmePath: readmePath)
        }
        let architecturePath = findArchitectureDoc(in: tracked)
            ?? ["ARCHITECTURE.md", "architecture.md", "docs/architecture.md"].first { fm.fileExists(atPath: main.appendingPathComponent($0).path) }
        let architecture: ArchitectureDoc? = historyFailed ? nil : architectureDoc(history: history, path: architecturePath)
        let summary = readmePath.flatMap { try? String(contentsOf: main.appendingPathComponent($0), encoding: .utf8) }.flatMap { readmeSummary($0) }

        let context = EvidenceContext(trackedFiles: tracked, history: history, planIntroducedBy: nil,
                                      fileExists: { FileManager.default.fileExists(atPath: main.appendingPathComponent($0).path) })
        var specs: [SpecSummary]?
        if !historyFailed && !trackedFailed {
            do { specs = try catalogSpecs(repo: main, context: context, overrides: work.overrides) } catch { note("specs: \(error)") }
        }

        var activeTasks: Int?
        if let vaultDirectory = work.vaultDirectory {
            let url = activeTasksURL(vaultRoot: vaultRoot, vaultDirectory: vaultDirectory)
            if let text = try? String(contentsOf: url, encoding: .utf8) { activeTasks = openCheckboxCount(text) }
        }

        var lastFetchAt: Date?
        if case .ok(let date) = fetchOutcome { lastFetchAt = date }
        let snapshot = ProjectSnapshot(
            projectId: work.projectId, day: today, scannedAt: Date(), status: status, fetch: fetchOutcome, lastFetchAt: lastFetchAt,
            lastCommitAt: history.first?.authorDate, readme: readme, spec: specs.map(headline), activeTasksOpen: activeTasks,
            error: errors.isEmpty ? nil : errors.map(\.message).joined(separator: "; "),
            architecture: architecture
        )
        return WorkResult(snapshot: snapshot, summary: summary, commitDays: historyFailed ? nil : commitsPerDay(history, calendar: calendar),
                          specs: specs, errors: errors)
    }

    private func updateVisibility(_ works: [Work], probe: any VisibilityProbing, now: Date, errors: inout [ScanError]) async {
        let cached = (try? store.visibilityChecks()) ?? [:]
        var due: [(id: String, repo: RemoteRepo)] = []
        for work in works {
            if work.unit.identity?.remoteResolved == false { continue }
            guard let repo = work.unit.identity?.remoteURL.flatMap(parseRemote) else {
                if cached[work.projectId] != nil { try? store.writeVisibility(projectId: work.projectId, nil) }
                continue
            }
            if let check = cached[work.projectId], check.visibility != .unknown, now.timeIntervalSince(check.checkedAt) < config.visibilityMaxAge { continue }
            due.append((work.projectId, repo))
        }
        let chunkSize = max(1, config.visibilityConcurrency)
        for start in stride(from: 0, to: due.count, by: chunkSize) {
            let chunk = Array(due[start..<min(start + chunkSize, due.count)])
            let answers = await withTaskGroup(of: (String, RepoVisibility).self) { group in
                for item in chunk { group.addTask { (item.id, await probe.visibility(of: item.repo)) } }
                var collected: [(String, RepoVisibility)] = []
                for await answer in group { collected.append(answer) }
                return collected
            }
            for (id, visibility) in answers {
                do { try store.writeVisibility(projectId: id, VisibilityCheck(visibility: visibility, checkedAt: Date())) } catch {
                    errors.append(ScanError(projectPath: nil, message: "Store: \(error)"))
                }
            }
        }
    }

    // MARK: Activity ingest

    private struct Parsed {
        var messages: [OwnerMessage] = []
        var sessions: [SessionObservation] = []
        var headers: [CodexSessionHeader] = []
        var malformed = 0
    }

    private func ingestFile(_ url: URL, _ errors: inout [ScanError], _ transform: ([Data]) -> Parsed) {
        var malformed = 0
        defer {
            if malformed > 0 { errors.append(ScanError(projectPath: url.path, message: "\(malformed) malformed lines skipped")) }
        }
        do {
            var previous = try store.cursor(for: url.path)
            // Parsing goes through Foundation (JSONSerialization, bridged strings), whose temporaries are autoreleased.
            // Without a pool per batch they pile up across every log file, and memory grows with the total log size.
            while true {
                let done = try autoreleasepool { () throws -> Bool in
                    let read = try readAppended(url, after: previous, maxBytes: config.ingestBatchBytes)
                    if read.lines.isEmpty && read.cursor == previous { return true }
                    let parsed = transform(read.lines)
                    malformed += parsed.malformed
                    try store.ingest(IngestBatch(messages: parsed.messages, sessions: parsed.sessions, codexHeaders: parsed.headers, cursor: (path: url.path, cursor: read.cursor)))
                    if read.lines.isEmpty || read.cursor.offset >= read.cursor.size { return true }
                    previous = read.cursor
                    return false
                }
                if done { return }
            }
        } catch {
            errors.append(ScanError(projectPath: url.path, message: "Cannot ingest: \(error.localizedDescription)"))
        }
    }

    private func listDirectory(_ url: URL, _ errors: inout [ScanError]) -> [URL]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        } catch {
            errors.append(ScanError(projectPath: url.path, message: "Cannot read \(url.path): \(error.localizedDescription)"))
            return nil
        }
    }

    private static let userMarker = Data("\"type\":\"user\"".utf8)
    private static let codexUserMarker = Data("\"role\":\"user\"".utf8)

    private func ingestClaude(_ errors: inout [ScanError]) {
        let history = config.claudeHome.appendingPathComponent("history.jsonl")
        if FileManager.default.fileExists(atPath: history.path) {
            ingestFile(history, &errors) { lines in
                Parsed(messages: lines.compactMap(parseClaudeHistoryLine))
            }
        }
        guard let projectDirs = listDirectory(config.claudeHome.appendingPathComponent("projects"), &errors) else { return }
        for dir in projectDirs {
            guard let files = listDirectory(dir, &errors) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                ingestFile(file, &errors) { lines in
                    var parsed = Parsed()
                    for line in lines where line.range(of: Self.userMarker) != nil {
                        switch parseClaudeTranscriptLine(line) {
                        case .record(let message): parsed.messages.append(message)
                        case .malformed: parsed.malformed += 1
                        case .skipped: break
                        }
                    }
                    let first = lines.lazy.compactMap(claudeSession(fromLine:)).first
                    let last = lines.reversed().lazy.compactMap(claudeSession(fromLine:)).first
                    var bySession: [String: SessionObservation] = [:]
                    for observation in [first, last].compactMap({ $0 }) {
                        let prior = bySession[observation.sessionId]
                        let times = [prior?.firstSeen, prior?.lastSeen, observation.timestamp].compactMap { $0 }
                        bySession[observation.sessionId] = SessionObservation(agent: .claude, sessionId: observation.sessionId, cwd: observation.cwd,
                                                                              firstSeen: times.min(), lastSeen: times.max(), delegated: observation.delegated || prior?.delegated == true)
                    }
                    parsed.sessions = Array(bySession.values)
                    return parsed
                }
            }
        }
    }

    private func ingestCodex(_ errors: inout [ScanError]) {
        let sessionsRoot = config.codexHome.appendingPathComponent("sessions")
        // Only dated folders: Finder leaves .DS_Store files next to them.
        func folders(_ url: URL) -> [URL] {
            (listDirectory(url, &errors) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        if FileManager.default.fileExists(atPath: sessionsRoot.path) {
            for year in folders(sessionsRoot) {
                for month in folders(year) {
                    for day in folders(month) {
                        for file in listDirectory(day, &errors) ?? [] where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                            ingestRollout(file, &errors)
                        }
                    }
                }
            }
        }
        let history = config.codexHome.appendingPathComponent("history.jsonl")
        if FileManager.default.fileExists(atPath: history.path) {
            ingestFile(history, &errors) { lines in
                var parsed = Parsed()
                for line in lines {
                    switch parseCodexHistoryLine(line) {
                    case .record(let entry) where !entry.isRelay:
                        parsed.messages.append(OwnerMessage(agent: .codex, sessionId: entry.sessionId, timestamp: entry.timestamp, cwd: nil, source: .history))
                    case .malformed: parsed.malformed += 1
                    default: break
                    }
                }
                return parsed
            }
        }
    }

    private func ingestRollout(_ file: URL, _ errors: inout [ScanError]) {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            errors.append(ScanError(projectPath: file.path, message: "Cannot open rollout"))
            return
        }
        var head = Data()
        let newline = UInt8(ascii: "\n")
        while head.count < 8 << 20, head.lazy.filter({ $0 == newline }).count < 5,
              let chunk = try? handle.read(upToCount: 262_144), !chunk.isEmpty {
            head.append(chunk)
        }
        try? handle.close()
        let firstLines = Array(head.split(separator: newline, omittingEmptySubsequences: true).prefix(5)).map { Data($0) }
        guard let header = parseCodexHeader(firstLines: firstLines) else { return }
        ingestFile(file, &errors) { lines in
            var parsed = Parsed()
            for line in lines where !header.isDelegated && line.range(of: Self.codexUserMarker) != nil {
                switch parseCodexRolloutLine(line, header: header) {
                case .record(let message): parsed.messages.append(message)
                case .malformed: parsed.malformed += 1
                case .skipped: break
                }
            }
            let stamps = [lines.lazy.compactMap(lineTimestamp).first, lines.reversed().lazy.compactMap(lineTimestamp).first, header.startedAt].compactMap { $0 }
            parsed.sessions = [SessionObservation(agent: .codex, sessionId: header.sessionId, cwd: header.cwd,
                                                  firstSeen: stamps.min(), lastSeen: stamps.max(), delegated: header.isDelegated)]
            parsed.headers = [header]
            return parsed
        }
    }
}

private func isInside(_ path: URL, _ root: URL) -> Bool {
    path.path == root.path || path.path.hasPrefix(root.path + "/")
}

private func lineTimestamp(_ line: Data) -> Date? {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
    return activityTimestamp(object["timestamp"])
}
