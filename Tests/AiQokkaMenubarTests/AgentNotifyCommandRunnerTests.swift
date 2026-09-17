@testable import AiQokkaMenubar
import Foundation
import XCTest

final class AgentNotifyCommandRunnerTests: XCTestCase {
    func testBuildsHealthNotificationAndPassesConfigThroughEnvironment() async throws {
        let executor = RecordingEnvironmentCommandExecutor(
            result: .success(CommandOutput(stdout: "{\"status\":\"published\"}", stderr: "", status: 0))
        )
        let configuration = UsageNtfyConfiguration(
            isEnabled: true,
            executablePath: "/custom/bin/agent-notify",
            configPath: "~/custom/agent-notify.env"
        )
        let milestone = UsageQuotaMilestone(
            providerID: "codex",
            providerName: "Codex",
            plan: "plus",
            windowLabel: "Weekly",
            usedPercent: 40.1,
            milestonePercent: 40,
            resetDate: nil
        )
        let runner = AgentNotifyCommandRunner(configuration: configuration, executor: executor)

        let delivered = await runner.send(milestone)

        XCTAssertTrue(delivered)
        let request = try XCTUnwrap(executor.request)
        XCTAssertEqual(request.executableURL.path, "/custom/bin/agent-notify")
        XCTAssertEqual(request.environment["AGENT_NOTIFY_CONFIG"],
                       ("~/custom/agent-notify.env" as NSString).expandingTildeInPath)
        XCTAssertEqual(request.arguments, [
            "send",
            "--source", "aiquokka",
            "--event", "health",
            "--title", "Codex Weekly 用量达到 40%",
            "--message", "当前已使用 40.1%，Codex（plus）Weekly 窗口没有可用的重置时间。",
            "--project", "aiquokka",
            "--tag", "aiquokka",
            "--tag", "quota"
        ])
    }

    func testNonZeroExitDoesNotReportDelivery() async {
        let executor = RecordingEnvironmentCommandExecutor(
            result: .success(CommandOutput(stdout: "", stderr: "unavailable", status: 1))
        )
        let runner = AgentNotifyCommandRunner(
            configuration: .testEnabled,
            executor: executor
        )

        let delivered = await runner.send(.testMilestone)

        XCTAssertFalse(delivered)
    }
}

private final class RecordingEnvironmentCommandExecutor: EnvironmentCommandExecutor, @unchecked Sendable {
    struct Request {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private let result: Result<CommandOutput, CommandExecutorError>
    private(set) var request: Request?

    init(result: Result<CommandOutput, CommandExecutorError>) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> CommandOutput {
        request = Request(executableURL: executableURL, arguments: arguments, environment: environment)
        return try result.get()
    }
}

private extension UsageNtfyConfiguration {
    static let testEnabled = UsageNtfyConfiguration(
        isEnabled: true,
        executablePath: "/bin/agent-notify",
        configPath: "/tmp/agent-notify.env"
    )
}

private extension UsageQuotaMilestone {
    static let testMilestone = UsageQuotaMilestone(
        providerID: "codex",
        providerName: "Codex",
        plan: "plus",
        windowLabel: "Weekly",
        usedPercent: 40,
        milestonePercent: 40,
        resetDate: nil
    )
}
