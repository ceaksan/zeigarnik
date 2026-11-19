import Foundation

public struct PlanTask: Sendable, Equatable, Codable {
    public let number: Int
    public let title: String
    public let createPaths: [String]
    public let modifyPaths: [String]
    public let testPaths: [String]
    public let checked: Int
    public let checkboxes: Int
    public let commitSubject: String?
    public let isExternal: Bool

    public init(number: Int, title: String, createPaths: [String], modifyPaths: [String], testPaths: [String], checked: Int, checkboxes: Int, commitSubject: String?, isExternal: Bool) {
        self.number = number
        self.title = title
        self.createPaths = createPaths
        self.modifyPaths = modifyPaths
        self.testPaths = testPaths
        self.checked = checked
        self.checkboxes = checkboxes
        self.commitSubject = commitSubject
        self.isExternal = isExternal
    }
}

public struct ParsedPlan: Sendable, Equatable {
    public let primarySpec: String?
    public let declaredStatus: String?
    public let tasks: [PlanTask]
}

private let externalTitleWords = ["release", "deploy", "manual", "orchestrator only", "orchestrator-only", "external", "deferred"]
private let externalMarkers = ["**external:**", "**manual:**", "**deferred:**"]

public func parsePlan(_ markdown: String) -> ParsedPlan {
    var primarySpec: String?
    var tasks: [PlanTask] = []
    var current: TaskBuilder?
    var inFence = false

    for raw in markdown.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            inFence.toggle()
            continue
        }
        if inFence { continue }

        if line.hasPrefix("## ") || line.hasPrefix("### ") {
            if let builder = current { tasks.append(builder.build()) }
            current = nil
            if let match = line.firstMatch(of: /^### Task (\d+):?\s*(.*)$/) {
                current = TaskBuilder(number: Int(match.1) ?? 0, title: String(match.2))
            }
            continue
        }

        if primarySpec == nil, line.hasPrefix("**Spec:**") {
            primarySpec = firstReference(in: String(line.dropFirst("**Spec:**".count)))
        }

        guard current != nil else { continue }
        if let match = line.firstMatch(of: /^- (Create|Modify|Test):(.*)$/) {
            let paths = parsePathList(String(match.2))
            switch match.1 {
            case "Create": current!.create += paths
            case "Modify": current!.modify += paths
            default: current!.test += paths
            }
        }
        if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
            current!.checked += 1
            current!.checkboxes += 1
        } else if line.hasPrefix("- [ ]") {
            current!.checkboxes += 1
        }
        if current!.commitSubject == nil, let match = line.firstMatch(of: /git commit -m "([^"]+)"/) {
            current!.commitSubject = String(match.1)
        }
        let prose = line.replacing(/`[^`]*`/, with: "").lowercased()
        if externalMarkers.contains(where: { prose.hasPrefix($0) }) {
            current!.external = true
        }
    }
    if let builder = current { tasks.append(builder.build()) }
    return ParsedPlan(primarySpec: primarySpec, declaredStatus: declaredStatus(markdown), tasks: tasks)
}

private struct TaskBuilder {
    let number: Int
    let title: String
    var create: [String] = []
    var modify: [String] = []
    var test: [String] = []
    var checked = 0
    var checkboxes = 0
    var commitSubject: String?
    var external = false

    init(number: Int, title: String) {
        self.number = number
        self.title = title
        let lower = title.lowercased()
        external = externalTitleWords.contains { lower.contains($0) }
    }

    func build() -> PlanTask {
        PlanTask(number: number, title: title, createPaths: create, modifyPaths: modify, testPaths: test,
                 checked: checked, checkboxes: checkboxes, commitSubject: commitSubject, isExternal: external)
    }
}

/// Backtick tokens outside parentheses that look like paths; siblings without a slash inherit the
/// directory of the last full path on the line; trailing line ranges are removed.
func parsePathList(_ text: String) -> [String] {
    let clean = text.replacing(/\([^)]*\)/, with: "")
    var paths: [String] = []
    var lastDirectory: String?
    for match in clean.matches(of: /`([^`\s]+)`/) {
        var token = String(match.1).replacing(/:[\d,\- ]+$/, with: "")
        guard token.contains("/") || token.contains(".") else { continue }
        if token.contains("/") {
            let directory = token.hasSuffix("/") ? token : (token as NSString).deletingLastPathComponent
            lastDirectory = directory.isEmpty ? nil : (directory.hasSuffix("/") ? directory : directory + "/")
        } else if let lastDirectory {
            token = lastDirectory + token
        }
        paths.append(token)
    }
    return paths
}

private func firstReference(in text: String) -> String? {
    if let match = text.firstMatch(of: /`([^`\s]+)`/) { return String(match.1) }
    if let match = text.firstMatch(of: /\]\(([^)\s]+)\)/) { return String(match.1) }
    return nil
}
