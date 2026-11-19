import Foundation

public struct CommitRecord: Sendable, Equatable, Codable {
    public let hash: String
    public let parents: [String]
    public let authorDate: Date
    public let subject: String
    public let files: [String]

    public init(hash: String, parents: [String], authorDate: Date, subject: String, files: [String]) {
        self.hash = hash
        self.parents = parents
        self.authorDate = authorDate
        self.subject = subject
        self.files = files
    }
}

/// Parses `git log --no-renames --format=%x1e%H%x1f%P%x1f%aI%x1f%s --name-only`, newest first.
public func parseLog(_ output: String) -> [CommitRecord] {
    let dateParser = ISO8601DateFormatter()
    dateParser.formatOptions = [.withInternetDateTime]
    return output.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { chunk in
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first else { return nil }
        let fields = header.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count == 4, let date = dateParser.date(from: String(fields[2])) else { return nil }
        return CommitRecord(
            hash: String(fields[0]),
            parents: fields[1].split(separator: " ").map(String.init),
            authorDate: date,
            subject: String(fields[3]),
            files: lines.dropFirst().map(String.init)
        )
    }
}

public func dayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

public func commitsPerDay(_ history: [CommitRecord], calendar: Calendar) -> [String: Int] {
    history.reduce(into: [:]) { counts, commit in
        counts[dayKey(commit.authorDate, calendar: calendar), default: 0] += 1
    }
}

extension GitInspector {
    public func history(_ repo: URL) async throws -> [CommitRecord] {
        let output = try await gitOrThrow(repo, ["log", "--no-renames", "--format=%x1e%H%x1f%P%x1f%aI%x1f%s", "--name-only"], timeout: .seconds(30))
        return parseLog(String(decoding: output, as: UTF8.self))
    }
}
