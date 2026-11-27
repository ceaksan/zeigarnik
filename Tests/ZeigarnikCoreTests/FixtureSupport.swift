import Foundation
@testable import ZeigarnikCore

func makeTestScanner(config: ScanConfig, store: Store, runner: CommandRunning,
                     visibilityProbe: (any VisibilityProbing)? = nil,
                     log: ScanLog = ScanLog(emit: { _ in })) -> ProjectScanner {
    ProjectScanner(config: config, store: store, runner: runner, visibilityProbe: visibilityProbe, log: log)
}

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent(name)
}

func fixture(_ name: String) -> String {
    (try? String(contentsOf: fixtureURL(name), encoding: .utf8)) ?? ""
}

func fixtureLines(_ name: String) -> [Data] {
    fixture(name).split(separator: "\n", omittingEmptySubsequences: true).map { Data($0.utf8) }
}

/// Selects the JSONL line whose `"_case"` key equals `tag`.
func fixtureLine(_ name: String, tag: String) -> Data {
    fixtureLines(name).first { line in
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return false }
        return object["_case"] as? String == tag
    } ?? Data()
}

func isoDate(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)!
}

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zg-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
