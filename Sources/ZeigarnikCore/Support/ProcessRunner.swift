import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32?
    public let stdout: Data
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32?, stdout: Data, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, cwd: cwd, environment: environment, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], cwd: URL?, environment: [String: String], timeout: Duration) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: nil, stdout: Data(), stderr: String(describing: error), timedOut: false)
        }

        let readers = DispatchGroup()
        let outBox = DataBox()
        let errBox = DataBox()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.set(out.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.set(err.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout.seconds) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        // A grandchild can keep a pipe open after the child exits; do not wait for it forever.
        _ = readers.wait(timeout: .now() + (timedOut ? 1 : 5))

        return CommandResult(
            exitCode: timedOut ? nil : process.terminationStatus,
            stdout: outBox.get(),
            stderr: String(decoding: errBox.get(), as: UTF8.self),
            timedOut: timedOut
        )
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) { lock.withLock { data = value } }
    func get() -> Data { lock.withLock { data } }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
