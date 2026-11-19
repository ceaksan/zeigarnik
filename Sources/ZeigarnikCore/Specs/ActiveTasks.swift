import Foundation

public func openCheckboxCount(_ markdown: String) -> Int {
    let (checked, total) = checkboxCounts(markdown)
    return total - checked
}

/// (checked, total) for `- [ ]` / `- [x]` items outside fenced code, at any indentation.
func checkboxCounts(_ markdown: String) -> (Int, Int) {
    var checked = 0
    var total = 0
    var inFence = false
    for raw in markdown.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            inFence.toggle()
            continue
        }
        if inFence { continue }
        if line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") {
            total += 1
        } else if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") || line.hasPrefix("* [x]") {
            total += 1
            checked += 1
        }
    }
    return (checked, total)
}

public func activeTasksURL(vaultRoot: URL, vaultDirectory: String) -> URL {
    vaultRoot.appendingPathComponent(vaultDirectory, isDirectory: true).appendingPathComponent("tasks/Active Tasks.md")
}
