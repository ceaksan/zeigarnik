import Foundation
import Darwin

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
        let out = Pipe()
        let err = Pipe()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        func failure(_ code: Int32) -> CommandResult {
            CommandResult(exitCode: nil, stdout: Data(), stderr: String(cString: strerror(code)), timedOut: false)
        }
        let actionsError = posix_spawn_file_actions_init(&actions)
        guard actionsError == 0 else { return failure(actionsError) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        let attributesError = posix_spawnattr_init(&attributes)
        guard attributesError == 0 else { return failure(attributesError) }
        defer { posix_spawnattr_destroy(&attributes) }
        // A parent-side setpgid races with exec. Spawn the child directly into its own group.
        var setupError: Int32 = 0
        func check(_ code: Int32) { if setupError == 0 { setupError = code } }
        check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        check(posix_spawnattr_setpgroup(&attributes, 0))
        check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        check(posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        check(posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        for handle in [out.fileHandleForReading, out.fileHandleForWriting, err.fileHandleForReading, err.fileHandleForWriting] {
            if handle.fileDescriptor > STDERR_FILENO { check(posix_spawn_file_actions_addclose(&actions, handle.fileDescriptor)) }
        }
        if let cwd { check(posix_spawn_file_actions_addchdir_np(&actions, cwd.path)) }
        guard setupError == 0 else { return failure(setupError) }
        let merged = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        var argv = ([executable] + arguments).map { strdup($0) } + [nil]
        var envp = merged.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        var pid: pid_t = 0
        let spawnError = argv.withUnsafeMutableBufferPointer { args in
            envp.withUnsafeMutableBufferPointer { env in
                posix_spawn(&pid, executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        guard spawnError == 0 else { return failure(spawnError) }

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

        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout.seconds)
        var status: Int32 = 0
        var exited = false
        var waitError: Int32?
        // WNOWAIT leaves the exited command unreaped, so its pid (and process group id) cannot be reused while helpers are killed.
        while true {
            var info = siginfo_t()
            let result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
            if result == 0 && info.si_pid == pid { exited = true; break }
            if result == -1 && errno != EINTR { waitError = errno; break }
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let timedOut = !exited && waitError == nil
        if exited {
            // The command is done: helpers left in its group are orphans. A helper in another session (an ssh
            // ControlPersist master) can still hold a pipe, so the wait for the output is bounded.
            kill(-pid, SIGKILL)
            _ = readers.wait(timeout: .now() + 5)
        } else {
            kill(-pid, SIGTERM)
            Thread.sleep(forTimeInterval: 0.1)
            kill(-pid, SIGKILL)
            _ = readers.wait(timeout: .now() + 1)
        }
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        if let waitError { return failure(waitError) }
        return CommandResult(
            exitCode: timedOut ? nil : (status & 0x7f == 0 ? (status >> 8) & 0xff : status & 0x7f),
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
