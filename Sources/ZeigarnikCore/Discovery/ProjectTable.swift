import Foundation

public struct ProjectTableRow: Sendable, Equatable {
    public let name: String
    public let directory: String?
    public let vaultDirectory: String?

    public init(name: String, directory: String?, vaultDirectory: String?) {
        self.name = name
        self.directory = directory
        self.vaultDirectory = vaultDirectory
    }
}

public func parseProjectTable(_ markdown: String) -> [ProjectTableRow] {
    var rows: [ProjectTableRow] = []
    var inSection = false
    var seenTable = false
    for rawLine in markdown.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("## ") {
            if inSection { break }
            inSection = line == "## Project Directories"
            continue
        }
        guard inSection else { continue }
        guard line.hasPrefix("|") else {
            if seenTable { break }
            continue
        }
        seenTable = true
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst().dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 3 else { continue }
        if cells[0] == "Project" || cells[0].allSatisfy({ $0 == "-" || $0 == ":" }) { continue }
        rows.append(ProjectTableRow(name: cells[0], directory: tableValue(cells[1]), vaultDirectory: tableValue(cells[2])))
    }
    return rows
}

private func tableValue(_ cell: String) -> String? {
    if cell.isEmpty || cell.hasPrefix("—") || cell == "Not registered" { return nil }
    return cell.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
}
