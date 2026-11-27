import Foundation
import os

public struct ScanLog: Sendable {
    enum Entry: Sendable, Equatable {
        case error(folder: String, path: String, message: String)
        case summary(projects: Int, errors: Int, duration: TimeInterval)
    }

    private let emit: @Sendable (Entry) -> Void
    private static let logger = Logger(subsystem: "com.ceaksan.zeigarnik", category: "scan")

    public init() {
        emit = Self.write
    }

    init(emit: @escaping @Sendable (Entry) -> Void) {
        self.emit = emit
    }

    func record(_ report: ScanReport) {
        for error in report.errors {
            let path = error.projectPath ?? ""
            let folder = error.projectPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "scan"
            emit(.error(folder: folder, path: path, message: scrubDiagnosticCredentials(error.message)))
        }
        emit(.summary(projects: report.projects, errors: report.errors.count, duration: report.finishedAt.timeIntervalSince(report.startedAt)))
    }

    private static func write(_ entry: Entry) {
        switch entry {
        case .error(let folder, let path, let message):
            logger.error("\(folder, privacy: .public) [\(path, privacy: .private)]: \(message, privacy: .public)")
        case .summary(let projects, let errors, let duration):
            logger.info("Scan finished: projects=\(projects, privacy: .public) errors=\(errors, privacy: .public) duration=\(duration, privacy: .public)s")
        }
    }
}
