import Foundation

private let dependencyManifestNames: Set<String> = ["Package.swift", "package.json", "pyproject.toml", "Cargo.toml"]

extension GitInspector {
    public func readmeState(_ repo: URL, history: [CommitRecord], readmePath: String?) async -> ReadmeDrift {
        guard let readmePath, let head = history.first,
              let baseline = history.first(where: { $0.files.contains(readmePath) }) else {
            return readmeDrift(history: history, readmePath: readmePath)
        }
        let paths = Set(history.prefix { $0.hash != baseline.hash }.flatMap(\.files))
            .filter { dependencyManifestNames.contains(($0 as NSString).lastPathComponent) }
        var unchanged = Set<String>()
        for path in paths.sorted() {
            guard let before = try? await gitOrThrow(repo, ["show", "\(baseline.hash):\(path)"]),
                  let after = try? await gitOrThrow(repo, ["show", "\(head.hash):\(path)"]),
                  let old = dependencySignature(String(decoding: before, as: UTF8.self), name: (path as NSString).lastPathComponent),
                  let new = dependencySignature(String(decoding: after, as: UTF8.self), name: (path as NSString).lastPathComponent),
                  old == new else { continue }
            unchanged.insert(path)
        }
        return readmeDrift(history: history, readmePath: readmePath, unchangedManifests: unchanged)
    }
}

func dependencySignature(_ text: String, name: String) -> [String]? {
    if name == "package.json" {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        let keys: Set<String> = ["dependencies", "devDependencies", "peerDependencies", "peerDependenciesMeta", "optionalDependencies",
                                 "bundleDependencies", "bundledDependencies", "overrides", "resolutions", "workspaces"]
        let selected = object.filter { keys.contains($0.key) }
        guard let data = try? JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys]) else { return nil }
        return [String(decoding: data, as: UTF8.self)]
    }
    guard let tokens = manifestTokens(text, swift: name == "Package.swift") else { return nil }
    if name == "Package.swift" {
        let tokens = tokens.filter { $0 != "\n" }
        guard !tokens.contains("#") else { return nil }
        guard tokens.indices.contains(where: { tokens[$0] == "Package" && $0 + 1 < tokens.count && tokens[$0 + 1] == "(" }) else { return nil }
        var signatures: [String] = []
        for index in tokens.indices where tokens[index] == "dependencies" {
            guard index + 2 < tokens.count, tokens[index + 1] == ":", tokens[index + 2] == "[" else { return nil }
            var end = index + 3
            var depth = 1
            while end < tokens.count && depth > 0 {
                if tokens[end] == "[" { depth += 1 }
                if tokens[end] == "]" { depth -= 1 }
                end += 1
            }
            guard depth == 0 else { return nil }
            guard end < tokens.count, [",", ")"].contains(tokens[end]) else { return nil }
            let body = Array(tokens[(index + 2)..<end])
            for i in body.indices {
                let token = body[i]
                if token.hasPrefix("\""), token.contains("\\(") { return nil }
                if token.first?.isLetter == true || token.hasPrefix("_") {
                    let label = i + 1 < body.count && body[i + 1] == ":"
                    let member = i > 0 && body[i - 1] == "."
                    guard label || member || ["true", "false", "nil"].contains(token) else { return nil }
                }
            }
            signatures.append(body.joined())
        }
        return signatures.sorted()
    }
    guard name == "Cargo.toml" || name == "pyproject.toml" else { return nil }
    var statements: [[String]] = []
    var current: [String] = []
    var depth = 0
    for token in tokens {
        if token == "\n" {
            if depth == 0 && !current.isEmpty { statements.append(current); current = [] }
            continue
        }
        if token == "[" || token == "{" { depth += 1 }
        if token == "]" || token == "}" { depth -= 1 }
        guard depth >= 0 else { return nil }
        current.append(token)
    }
    guard depth == 0 else { return nil }
    if !current.isEmpty { statements.append(current) }
    var section = ""
    var signatures: [String] = []
    for statement in statements {
        if statement.first == "[" && statement.last == "]" {
            section = statement.drop(while: { $0 == "[" }).reversed().drop(while: { $0 == "]" }).reversed().joined()
            continue
        }
        guard let equals = statement.firstIndex(of: "="), equals > 0, equals + 1 < statement.count else { return nil }
        let key = statement[..<equals].joined().trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let value = statement[(equals + 1)...]
        if name == "pyproject.toml", section == "project", key == "dynamic",
           value.contains(where: { $0.contains("dependencies") }) { return nil }
        let fullKey = section.isEmpty ? key : section + "." + key
        let dependencySection = fullKey.split(separator: ".").contains {
            ["dependencies", "dev-dependencies", "build-dependencies", "optional-dependencies", "dependency-groups", "patch", "replace"].contains(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        }
        let selected: Bool
        if name == "Cargo.toml" {
            selected = dependencySection || section == "features"
        } else {
            selected = dependencySection || (section == "project" && ["dependencies", "optional-dependencies"].contains(key))
                || (section == "build-system" && key == "requires") || section == "tool.uv.sources"
        }
        if selected { signatures.append(section + ":" + statement.joined()) }
    }
    return signatures.sorted()
}

// Read declarations without evaluating manifests. Unsupported dynamic values retain the conservative drift rule.
private func manifestTokens(_ text: String, swift: Bool) -> [String]? {
    let chars = Array(text)
    var index = 0
    var result: [String] = []
    while index < chars.count {
        let c = chars[index]
        if c == "\n" { result.append("\n"); index += 1; continue }
        if c.isWhitespace { index += 1; continue }
        if (!swift && c == "#") || (swift && c == "/" && index + 1 < chars.count && chars[index + 1] == "/") {
            while index < chars.count && chars[index] != "\n" { index += 1 }
            continue
        }
        if swift && c == "/" && index + 1 < chars.count && chars[index + 1] == "*" {
            var depth = 1
            index += 2
            while index + 1 < chars.count && depth > 0 {
                if chars[index] == "/" && chars[index + 1] == "*" { depth += 1; index += 2 }
                else if chars[index] == "*" && chars[index + 1] == "/" { depth -= 1; index += 2 }
                else { index += 1 }
            }
            guard depth == 0 else { return nil }
            continue
        }
        if c == "\"" || c == "'" {
            let start = index
            let triple = index + 2 < chars.count && chars[index + 1] == c && chars[index + 2] == c
            let width = triple ? 3 : 1
            index += width
            var closed = false
            while index < chars.count {
                if c == "\"" && chars[index] == "\\" { index += 2; continue }
                if chars[index] == c && (!triple || (index + 2 < chars.count && chars[index + 1] == c && chars[index + 2] == c)) {
                    index += width
                    closed = true
                    break
                }
                index += 1
            }
            guard closed else { return nil }
            result.append(String(chars[start..<index]))
        } else if c.isLetter || c.isNumber || c == "_" || c == "-" {
            let start = index
            repeat { index += 1 } while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_" || chars[index] == "-")
            result.append(String(chars[start..<index]))
        } else {
            result.append(String(c))
            index += 1
        }
    }
    return result
}
