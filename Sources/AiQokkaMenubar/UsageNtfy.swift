import Combine
import Foundation

struct UsageNtfyConfiguration: Equatable, Sendable {
    static let defaultMilestoneStepPercent = 10
    static let milestoneStepRange = 1...50

    let isEnabled: Bool
    let executablePath: String
    let configPath: String
    let milestoneStepPercent: Int

    init(
        isEnabled: Bool,
        executablePath: String,
        configPath: String,
        milestoneStepPercent: Int = Self.defaultMilestoneStepPercent
    ) {
        self.isEnabled = isEnabled
        self.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configPath = configPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.milestoneStepPercent = Self.normalizedMilestoneStep(milestoneStepPercent)
    }

    static func normalizedMilestoneStep(_ value: Int) -> Int {
        milestoneStepRange.contains(value) ? value : defaultMilestoneStepPercent
    }

    var isConfigured: Bool {
        isEnabled && !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var executableURL: URL {
        URL(fileURLWithPath: Self.expandedPath(executablePath))
    }

    var configURL: URL {
        URL(fileURLWithPath: Self.expandedPath(configPath))
    }

    static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

@MainActor
final class UsageNtfySettings: ObservableObject {
    static let enabledKey = "aiquokka.ntfy.enabled"
    static let executablePathKey = "aiquokka.ntfy.agentNotifyExecutablePath"
    static let configPathKey = "aiquokka.ntfy.agentNotifyConfigPath"
    static let milestoneStepPercentKey = "aiquokka.ntfy.milestoneStepPercent"

    @Published var isEnabled: Bool {
        didSet { userDefaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var agentNotifyExecutablePath: String {
        didSet { userDefaults.set(agentNotifyExecutablePath, forKey: Self.executablePathKey) }
    }

    @Published var agentNotifyConfigPath: String {
        didSet { userDefaults.set(agentNotifyConfigPath, forKey: Self.configPathKey) }
    }

    @Published var milestoneStepPercent: Int {
        didSet {
            let normalized = UsageNtfyConfiguration.normalizedMilestoneStep(milestoneStepPercent)
            if normalized != milestoneStepPercent {
                milestoneStepPercent = normalized
            } else {
                userDefaults.set(normalized, forKey: Self.milestoneStepPercentKey)
            }
        }
    }

    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.isEnabled = userDefaults.object(forKey: Self.enabledKey) as? Bool ?? false
        self.agentNotifyExecutablePath = userDefaults.string(forKey: Self.executablePathKey)
            ?? Self.defaultExecutablePath(homeDirectory: homeDirectory, fileManager: fileManager)
        self.agentNotifyConfigPath = userDefaults.string(forKey: Self.configPathKey)
            ?? homeDirectory.appendingPathComponent(".config/agent-notify/agent-notify.env").path
        let storedStep = (userDefaults.object(forKey: Self.milestoneStepPercentKey) as? NSNumber)?.intValue
            ?? UsageNtfyConfiguration.defaultMilestoneStepPercent
        self.milestoneStepPercent = UsageNtfyConfiguration.normalizedMilestoneStep(storedStep)
    }

    var configuration: UsageNtfyConfiguration {
        UsageNtfyConfiguration(
            isEnabled: isEnabled,
            executablePath: agentNotifyExecutablePath,
            configPath: agentNotifyConfigPath,
            milestoneStepPercent: milestoneStepPercent
        )
    }

    var statusText: String {
        guard isEnabled else { return "未启用，不会发送 ntfy 消息。" }
        guard configuration.isConfigured else { return "请填写 agent-notify 可执行文件和配置文件。" }

        let executablePath = UsageNtfyConfiguration.expandedPath(configuration.executablePath)
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            return "找不到可执行的 agent-notify，请检查路径。"
        }

        let configPath = UsageNtfyConfiguration.expandedPath(configuration.configPath)
        guard fileManager.fileExists(atPath: configPath) else {
            return "找不到 ntfy 配置文件，请检查路径。"
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: configPath),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue == 0o600
        else {
            return "ntfy 配置文件权限必须为 0600，请先执行 chmod 600。"
        }

        return "已启用；达到新的 \(milestoneStepPercent)% 用量档位时发送一次。"
    }

    static func defaultExecutablePath(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> String {
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/agent-notify"),
            URL(fileURLWithPath: "/opt/homebrew/bin/agent-notify"),
            URL(fileURLWithPath: "/usr/local/bin/agent-notify")
        ]
        if let installedPath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })?.path {
            return installedPath
        }

        // Keep the known local gateway path useful without probing a protected
        // Documents directory during startup. The actual access check happens
        // only after the user enables ntfy.
        return homeDirectory
            .appendingPathComponent("Documents/Work/Sources/tailscale_ops/agent-notify/.venv/bin/agent-notify")
            .path
    }
}

protocol EnvironmentCommandExecutor: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration
    ) async throws -> CommandOutput
}

struct AgentNotifyCommandRunner: Sendable {
    static let timeout: Duration = .seconds(15)

    let configuration: UsageNtfyConfiguration
    private let executor: any EnvironmentCommandExecutor

    init(
        configuration: UsageNtfyConfiguration,
        executor: any EnvironmentCommandExecutor = ProcessCommandExecutor()
    ) {
        self.configuration = configuration
        self.executor = executor
    }

    func send(_ milestone: UsageQuotaMilestone) async -> Bool {
        guard configuration.isConfigured else { return false }

        let arguments = [
            "send",
            "--source", "aiquokka",
            "--event", "health",
            "--title", milestone.notificationTitle,
            "--message", milestone.notificationBody,
            "--project", "aiquokka",
            "--tag", "aiquokka",
            "--tag", "quota"
        ]

        do {
            let output = try await executor.run(
                executableURL: configuration.executableURL,
                arguments: arguments,
                environment: ["AGENT_NOTIFY_CONFIG": configuration.configURL.path],
                timeout: Self.timeout
            )
            return output.status == 0
        } catch {
            return false
        }
    }
}

@MainActor
final class AgentNotifyUsageMilestoneNotificationClient: UsageMilestoneNotificationClient {
    func send(
        _ milestone: UsageQuotaMilestone,
        configuration: UsageNtfyConfiguration
    ) async -> Bool {
        await AgentNotifyCommandRunner(configuration: configuration).send(milestone)
    }
}
