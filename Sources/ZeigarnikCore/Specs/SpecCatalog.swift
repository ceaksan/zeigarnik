import Foundation

public struct SpecSummary: Sendable, Equatable, Codable {
    public let specPath: String
    public let planPath: String?
    public let planPaths: [String]
    public let date: String?
    public let title: String
    public let declared: String?
    public let stage: SpecStage
    public let evidence: PlanEvidence?

    public init(specPath: String, planPath: String?, date: String?, title: String, declared: String?, stage: SpecStage, evidence: PlanEvidence?, planPaths: [String] = []) {
        let paths = planPaths.isEmpty ? (planPath.map { [$0] } ?? []) : planPaths
        self.specPath = specPath
        self.planPaths = paths.sorted()
        self.planPath = self.planPaths.last
        self.date = date
        self.title = title
        self.declared = declared
        self.stage = stage
        self.evidence = evidence
    }

    private enum CodingKeys: String, CodingKey {
        case specPath, planPath, planPaths, date, title, declared, stage, evidence
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            specPath: try values.decode(String.self, forKey: .specPath),
            planPath: try values.decodeIfPresent(String.self, forKey: .planPath),
            date: try values.decodeIfPresent(String.self, forKey: .date),
            title: try values.decode(String.self, forKey: .title),
            declared: try values.decodeIfPresent(String.self, forKey: .declared),
            stage: try values.decode(SpecStage.self, forKey: .stage),
            evidence: try values.decodeIfPresent(PlanEvidence.self, forKey: .evidence),
            planPaths: try values.decodeIfPresent([String].self, forKey: .planPaths) ?? []
        )
    }
}

public struct SpecHeadline: Sendable, Equatable, Codable {
    public let current: SpecSummary?
    public let lastDone: SpecSummary?

    public init(current: SpecSummary?, lastDone: SpecSummary?) {
        self.current = current
        self.lastDone = lastDone
    }
}

private let specDirectories = ["docs/superpowers/specs", "docs/specs", "specs"]
private let planDirectories = ["docs/superpowers/plans", "docs/plans"]

public func catalogSpecs(repo: URL, context: EvidenceContext, overrides: [String: OwnerSpecOverride]) throws -> [SpecSummary] {
    let specs = markdownFiles(repo, specDirectories)
    let plans = markdownFiles(repo, planDirectories)
    var summaries: [SpecSummary] = []
    var linkedPlans = Set<String>()

    var plansForSpec: [String: [(path: String, parsed: ParsedPlan)]] = [:]
    for planPath in plans.sorted() {
        let parsed = parsePlan(read(repo, planPath))
        var target: String?
        if let reference = parsed.primarySpec { target = normalizeReference(reference, from: planPath, repo: repo) }
        if target == nil || !specs.contains(target!) {
            let name = (planPath as NSString).lastPathComponent
            let designName = (name as NSString).deletingPathExtension + "-design.md"
            target = specs.first { ($0 as NSString).lastPathComponent == designName || ($0 as NSString).lastPathComponent == name }
        }
        if let target, specs.contains(target) {
            plansForSpec[target, default: []].append((planPath, parsed))
            linkedPlans.insert(planPath)
        }
    }

    func planEvidence(_ planPath: String, _ parsed: ParsedPlan) -> PlanEvidence {
        let introduced = context.history.last { $0.files.contains(planPath) }?.hash
        let ctx = EvidenceContext(trackedFiles: context.trackedFiles, history: context.history, planIntroducedBy: introduced, fileExists: context.fileExists)
        return PlanEvidence(tasks: parsed.tasks.map { evaluate($0, in: ctx) })
    }

    for specPath in specs {
        let text = read(repo, specPath)
        let linked = plansForSpec[specPath] ?? []
        let evidence: PlanEvidence? = linked.isEmpty ? nil
            : PlanEvidence(tasks: linked.flatMap { planEvidence($0.path, $0.parsed).tasks })
        let planDeclared: String?
        if let status = linked.last?.parsed.declaredStatus,
           linked.allSatisfy({ classifyStatus($0.parsed.declaredStatus) == classifyStatus(status) }) {
            planDeclared = status
        } else {
            planDeclared = nil
        }
        let declared = declaredStatus(text) ?? planDeclared
        summaries.append(SpecSummary(
            specPath: specPath, planPath: linked.last?.path, date: datePrefix(specPath), title: title(text, fallback: specPath),
            declared: declared,
            stage: specStage(declared: declared, plan: evidence, override: overrides[specPath]),
            evidence: evidence, planPaths: linked.map(\.path)
        ))
    }
    for planPath in plans where !linkedPlans.contains(planPath) {
        let text = read(repo, planPath)
        let parsed = parsePlan(text)
        let evidence = planEvidence(planPath, parsed)
        summaries.append(SpecSummary(
            specPath: planPath, planPath: planPath, date: datePrefix(planPath), title: title(text, fallback: planPath),
            declared: parsed.declaredStatus,
            stage: specStage(declared: parsed.declaredStatus, plan: evidence, override: overrides[planPath]),
            evidence: evidence
        ))
    }
    summaries += openSpecChanges(repo)
    if FileManager.default.fileExists(atPath: repo.appendingPathComponent("SHARED_TASK_NOTES.md").path) {
        let text = read(repo, "SHARED_TASK_NOTES.md")
        let (checked, total) = checkboxCounts(text)
        let stage: SpecStage = total == 0 ? .design : (checked == total ? .done : .inProgress(done: checked, total: total, external: 0))
        summaries.append(SpecSummary(specPath: "SHARED_TASK_NOTES.md", planPath: nil, date: nil, title: title(text, fallback: "SHARED_TASK_NOTES.md"),
                                     declared: nil, stage: overrides["SHARED_TASK_NOTES.md"] == .done ? .done : stage, evidence: nil))
    }
    return summaries
}

public func headline(_ specs: [SpecSummary]) -> SpecHeadline {
    let ordered = specs.sorted { ($0.date ?? "", $0.specPath) < ($1.date ?? "", $1.specPath) }
    return SpecHeadline(current: ordered.last { $0.stage != .done }, lastDone: ordered.last { $0.stage == .done })
}

private func markdownFiles(_ repo: URL, _ directories: [String]) -> [String] {
    directories.flatMap { directory -> [String] in
        let url = repo.appendingPathComponent(directory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasSuffix(".md") && !$0.hasPrefix("_") }.map { directory + "/" + $0 }
    }.sorted()
}

private func read(_ repo: URL, _ path: String) -> String {
    (try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func normalizeReference(_ reference: String, from planPath: String, repo: URL) -> String? {
    let clean = reference.components(separatedBy: "#").first ?? reference
    if FileManager.default.fileExists(atPath: repo.appendingPathComponent(clean).path) { return clean }
    let relative = ((planPath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(clean)
    let standardized = (relative as NSString).standardizingPath
    return FileManager.default.fileExists(atPath: repo.appendingPathComponent(standardized).path) ? standardized : nil
}

private func datePrefix(_ path: String) -> String? {
    let name = (path as NSString).lastPathComponent
    guard let match = name.firstMatch(of: /^(\d{4}-\d{2}-\d{2})/) else { return nil }
    return String(match.1)
}

private func title(_ text: String, fallback: String) -> String {
    for line in text.components(separatedBy: "\n") where line.hasPrefix("# ") {
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    return (fallback as NSString).lastPathComponent
}

private func openSpecChanges(_ repo: URL) -> [SpecSummary] {
    let fm = FileManager.default
    var result: [SpecSummary] = []
    func add(_ relative: String, archived: Bool) {
        let tasks = read(repo, relative + "/tasks.md")
        let (checked, total) = checkboxCounts(tasks)
        let stage: SpecStage = archived ? .done : .inProgress(done: checked, total: total, external: 0)
        result.append(SpecSummary(specPath: relative, planPath: nil, date: datePrefix(relative), title: (relative as NSString).lastPathComponent,
                                  declared: nil, stage: stage, evidence: nil))
    }
    let changes = "openspec/changes"
    for name in ((try? fm.contentsOfDirectory(atPath: repo.appendingPathComponent(changes).path)) ?? []).sorted() where !name.hasPrefix(".") {
        if name == "archive" {
            for archived in ((try? fm.contentsOfDirectory(atPath: repo.appendingPathComponent(changes + "/archive").path)) ?? []).sorted() where !archived.hasPrefix(".") {
                add(changes + "/archive/" + archived, archived: true)
            }
        } else {
            add(changes + "/" + name, archived: false)
        }
    }
    return result
}
