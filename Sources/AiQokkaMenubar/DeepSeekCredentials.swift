import Foundation
import Security

protocol DeepSeekCredentialStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

enum DeepSeekCredentialError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? { "无法访问 DeepSeek 凭据。" }
}

final class KeychainDeepSeekCredentialStore: DeepSeekCredentialStore, @unchecked Sendable {
    static let service = "io.github.sheneyan.aiquokka-menubar.deepseek"
    static let account = "DEEPSEEK_API_KEY"

    func load() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw DeepSeekCredentialError.unavailable }
        return key
    }

    func save(_ key: String) throws {
        let identity: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw DeepSeekCredentialError.unavailable }
        var add = identity
        add[kSecValueData] = Data(key.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw DeepSeekCredentialError.unavailable }
    }

    func delete() throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DeepSeekCredentialError.unavailable }
    }
}
