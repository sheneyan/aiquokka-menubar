import Foundation

protocol UsageEnvironmentProviding: Sendable {
    func environment() throws -> [String: String]
}

struct EmptyUsageEnvironmentProvider: UsageEnvironmentProviding {
    func environment() throws -> [String: String] { [:] }
}

struct DeepSeekEnvironmentProvider: UsageEnvironmentProviding {
    let credentialStore: any DeepSeekCredentialStore

    func environment() throws -> [String: String] {
        guard let key = try credentialStore.load(), !key.isEmpty else { return [:] }
        return ["DEEPSEEK_API_KEY": key]
    }
}
