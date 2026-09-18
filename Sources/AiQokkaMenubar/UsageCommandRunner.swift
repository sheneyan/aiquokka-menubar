import Foundation

struct CommandOutput: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
}

enum CommandExecutorError: Error, Equatable, LocalizedError {
    case timeout
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "aiquokka did not finish within 30 seconds."
        case let .launchFailed(message):
            return "aiquokka could not be started: \(message)"
        }
    }
}

protocol CommandExecutor: Sendable {
    func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> CommandOutput
}

enum UsageCommandError: Error, Equatable, LocalizedError {
    case commandNotFound(attemptedPaths: [String])
    case nonZeroExit(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .commandNotFound(attemptedPaths):
            return "Could not find aiquokka. Tried: \(attemptedPaths.joined(separator: ", "))"
        case let .nonZeroExit(status, stderr):
            let detail = stderr.isEmpty ? "no error output" : stderr
            return "aiquokka exited with status \(status): \(detail)"
        }
    }
}

struct UsageCommandRunner: Sendable {
    static let timeout: Duration = .seconds(30)

    let candidatePaths: [URL]
    private let isExecutable: @Sendable (URL) -> Bool
    private let executor: any EnvironmentCommandExecutor
    private let environmentProvider: any UsageEnvironmentProviding

    init(
        candidatePaths: [URL] = Self.defaultCandidatePaths(),
        isExecutable: @escaping @Sendable (URL) -> Bool = { url in
            FileManager.default.isExecutableFile(atPath: url.path)
        },
        executor: any EnvironmentCommandExecutor = ProcessCommandExecutor(),
        environmentProvider: any UsageEnvironmentProviding = EmptyUsageEnvironmentProvider()
    ) {
        var seen = Set<String>()
        self.candidatePaths = candidatePaths.filter { seen.insert($0.path).inserted }
        self.isExecutable = isExecutable
        self.executor = executor
        self.environmentProvider = environmentProvider
    }

    func fetchYAML() async throws -> String {
        guard let executableURL = candidatePaths.first(where: isExecutable) else {
            throw UsageCommandError.commandNotFound(attemptedPaths: candidatePaths.map(\.path))
        }

        let output = try await executor.run(
            executableURL: executableURL,
            arguments: ["--yml"],
            environment: try environmentProvider.environment(),
            timeout: Self.timeout
        )
        guard output.status == 0 else {
            throw UsageCommandError.nonZeroExit(status: output.status, stderr: output.stderr)
        }
        return output.stdout
    }

    static func defaultCandidatePaths(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> [URL] {
        var paths = [
            URL(fileURLWithPath: "/opt/homebrew/bin/aiquokka"),
            URL(fileURLWithPath: "/usr/local/bin/aiquokka"),
            homeDirectory.appending(path: "go/bin/aiquokka")
        ]

        if let pathEnvironment {
            paths.append(contentsOf: pathEnvironment.split(separator: ":").map { directory in
                URL(fileURLWithPath: String(directory)).appendingPathComponent("aiquokka")
            })
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0.path).inserted }
    }
}

final class ProcessCommandExecutor: CommandExecutor, EnvironmentCommandExecutor, @unchecked Sendable {
    private let proxyEnvironment: any ProxyEnvironmentProviding

    init(proxyEnvironment: any ProxyEnvironmentProviding = SystemProxyEnvironment()) {
        self.proxyEnvironment = proxyEnvironment
    }

    func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> CommandOutput {
        try await run(executableURL: executableURL, arguments: arguments, environment: [:], timeout: timeout)
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment extraEnvironment: [String: String],
        timeout: Duration
    ) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let gate = ProcessExecutionGate()
            let finish: @Sendable (Result<CommandOutput, Error>) -> Void = { result in
                guard gate.claim() else { return }

                switch result {
                case let .success(output):
                    continuation.resume(returning: output)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            var environment = ProcessInfo.processInfo.environment
            environment.merge(proxyEnvironment.environmentVariables()) { _, resolved in resolved }
            environment.merge(extraEnvironment) { _, resolved in resolved }
            process.environment = environment
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                finish(.success(CommandOutput(stdout: stdout, stderr: stderr, status: process.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(CommandExecutorError.launchFailed(error.localizedDescription)))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
                guard gate.claim() else { return }

                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(throwing: CommandExecutorError.timeout)
            }
        }
    }
}

private final class ProcessExecutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
