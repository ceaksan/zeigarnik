import Foundation

public enum TaskEvidence: Sendable, Equatable, Codable {
    case done
    case pending(missing: [String])
    case external
    case noEvidence
}

public struct TaskEvidenceDetail: Sendable, Equatable, Codable {
    public let number: Int
    public let title: String
    public let evidence: TaskEvidence
    public let resolvedPaths: [String]
    public let matchedCommits: [String]

    public init(number: Int, title: String, evidence: TaskEvidence, resolvedPaths: [String], matchedCommits: [String]) {
        self.number = number
        self.title = title
        self.evidence = evidence
        self.resolvedPaths = resolvedPaths
        self.matchedCommits = matchedCommits
    }
}

public struct EvidenceContext: Sendable {
    public let trackedFiles: Set<String>
    public let history: [CommitRecord]
    public let planIntroducedBy: String?
    public let fileExists: @Sendable (String) -> Bool

    public init(trackedFiles: Set<String>, history: [CommitRecord], planIntroducedBy: String?, fileExists: @escaping @Sendable (String) -> Bool) {
        self.trackedFiles = trackedFiles
        self.history = history
        self.planIntroducedBy = planIntroducedBy
        self.fileExists = fileExists
    }
}

public struct PlanEvidence: Sendable, Equatable, Codable {
    public let tasks: [TaskEvidenceDetail]
    public var done: Int
    public var denominator: Int
    public var external: Int

    public init(tasks: [TaskEvidenceDetail]) {
        self.tasks = tasks
        done = tasks.filter { $0.evidence == .done }.count
        denominator = tasks.filter { $0.evidence != .noEvidence }.count
        external = tasks.filter { $0.evidence == .external }.count
    }
}

public enum OwnerSpecOverride: String, Sendable, Codable {
    case done, notDone
}

public enum SpecStage: Sendable, Equatable, Codable {
    case design
    case inProgress(done: Int, total: Int, external: Int)
    case declaredDone(done: Int, total: Int)
    case done
}

public func evaluate(_ task: PlanTask, in context: EvidenceContext) -> TaskEvidenceDetail {
    var resolved: [String] = []
    var missing: [String] = []
    var commits: [String] = []

    let introducedIndex = context.planIntroducedBy.flatMap { hash in context.history.firstIndex { $0.hash == hash } }
    let window = introducedIndex.map { Array(context.history[...$0]) } ?? []
    var subjectCommit: CommitRecord?
    if let subject = task.commitSubject {
        let taskPaths = Set(task.createPaths + task.modifyPaths + task.testPaths)
        subjectCommit = context.history.first { $0.subject == subject && !Set($0.files).isDisjoint(with: taskPaths) }
    }

    for path in task.createPaths + task.testPaths {
        let matches = resolveExisting(path, in: context)
        if matches.isEmpty { missing.append(path) } else { resolved += matches }
    }
    for path in task.modifyPaths {
        let touching = (window + [subjectCommit].compactMap { $0 }).filter { commit in commit.files.contains { pathMatches(path, $0) } }
        if touching.isEmpty {
            missing.append(path)
        } else {
            resolved.append(path)
            for commit in touching where !commits.contains(commit.hash) { commits.append(commit.hash) }
        }
    }
    if let subjectCommit, !commits.contains(subjectCommit.hash) { commits.append(subjectCommit.hash) }

    let hasPaths = !(task.createPaths.isEmpty && task.modifyPaths.isEmpty && task.testPaths.isEmpty)
    let evidence: TaskEvidence
    if task.isExternal {
        evidence = .external
    } else if hasPaths {
        evidence = missing.isEmpty ? .done : .pending(missing: missing)
    } else if task.checkboxes > 0 {
        evidence = task.checked == task.checkboxes ? .done : .pending(missing: [])
    } else {
        evidence = .noEvidence
    }
    return TaskEvidenceDetail(number: task.number, title: task.title, evidence: evidence, resolvedPaths: resolved, matchedCommits: commits)
}

private func resolveExisting(_ path: String, in context: EvidenceContext) -> [String] {
    if path.contains("*") {
        return context.trackedFiles.filter { fnmatch(path, $0, 0) == 0 }.sorted()
    }
    if path.hasSuffix("/") {
        let under = context.trackedFiles.filter { $0.hasPrefix(path) }.sorted()
        return under.isEmpty && context.fileExists(path) ? [path] : under
    }
    return context.trackedFiles.contains(path) || context.fileExists(path) ? [path] : []
}

private func pathMatches(_ pattern: String, _ file: String) -> Bool {
    if pattern.contains("*") { return fnmatch(pattern, file, 0) == 0 }
    if pattern.hasSuffix("/") { return file.hasPrefix(pattern) }
    return pattern == file
}

public func specStage(declared: String?, plan: PlanEvidence?, override: OwnerSpecOverride?) -> SpecStage {
    switch override {
    case .done:
        return .done
    case .notDone:
        guard let plan, plan.denominator > 0 else { return .design }
        return .inProgress(done: plan.done, total: plan.denominator, external: plan.external)
    case nil:
        break
    }
    guard let plan, plan.denominator > 0 else { return .design }
    if plan.denominator > 0, plan.done == plan.denominator, plan.external == 0 { return .done }
    if classifyStatus(declared) == .completion { return .declaredDone(done: plan.done, total: plan.denominator) }
    return .inProgress(done: plan.done, total: plan.denominator, external: plan.external)
}
