@testable import AiQokkaMenubar
import Foundation
import XCTest

final class UsageCommandRunnerTests: XCTestCase {
    func testUsesFirstExecutableCandidateAndYAMLArgument() async throws {
        let executor = RecordingCommandExecutor(result: .success(.init(stdout: "codex: {}", stderr: "", status: 0)))
        let candidates = [URL(fileURLWithPath: "/first/aiquokka"), URL(fileURLWithPath: "/second/aiquokka")]
        let runner = UsageCommandRunner(
            candidatePaths: candidates,
            isExecutable: { $0.path == "/second/aiquokka" },
            executor: executor
        )

        let output = try await runner.fetchYAML()

        XCTAssertEqual(output, "codex: {}")
        XCTAssertEqual(executor.requests.count, 1)
        XCTAssertEqual(executor.requests[0].executableURL, candidates[1])
        XCTAssertEqual(executor.requests[0].arguments, ["--yml"])
    }

    func testNotFoundIncludesAllAttemptedPaths() async {
        let executor = RecordingCommandExecutor(result: .success(.init(stdout: "", stderr: "", status: 0)))
        let candidates = [URL(fileURLWithPath: "/one/aiquokka"), URL(fileURLWithPath: "/two/aiquokka")]
        let runner = UsageCommandRunner(
            candidatePaths: candidates,
            isExecutable: { _ in false },
            executor: executor
        )

        do {
            _ = try await runner.fetchYAML()
            XCTFail("Expected commandNotFound")
        } catch let error as UsageCommandError {
            guard case let .commandNotFound(attemptedPaths) = error else {
                return XCTFail("Unexpected command error: \(error)")
            }
            XCTAssertEqual(attemptedPaths, candidates.map(\.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonZeroExitPreservesCodeAndStderr() async {
        let executor = RecordingCommandExecutor(
            result: .success(.init(stdout: "", stderr: "not logged in", status: 7))
        )
        let runner = UsageCommandRunner(
            candidatePaths: [URL(fileURLWithPath: "/bin/aiquokka")],
            isExecutable: { _ in true },
            executor: executor
        )

        do {
            _ = try await runner.fetchYAML()
            XCTFail("Expected nonZeroExit")
        } catch let error as UsageCommandError {
            guard case let .nonZeroExit(status, stderr) = error else {
                return XCTFail("Unexpected command error: \(error)")
            }
            XCTAssertEqual(status, 7)
            XCTAssertEqual(stderr, "not logged in")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExecutorTimeoutIsPropagated() async {
        let executor = RecordingCommandExecutor(result: .failure(.timeout))
        let runner = UsageCommandRunner(
            candidatePaths: [URL(fileURLWithPath: "/bin/aiquokka")],
            isExecutable: { _ in true },
            executor: executor
        )

        do {
            _ = try await runner.fetchYAML()
            XCTFail("Expected timeout")
        } catch let error as CommandExecutorError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class RecordingCommandExecutor: CommandExecutor, @unchecked Sendable {
    struct Request: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private let result: Result<CommandOutput, CommandExecutorError>
    private(set) var requests: [Request] = []

    init(result: Result<CommandOutput, CommandExecutorError>) {
        self.result = result
    }

    func run(executableURL: URL, arguments: [String], timeout: Duration) async throws -> CommandOutput {
        requests.append(Request(executableURL: executableURL, arguments: arguments))
        return try result.get()
    }
}
