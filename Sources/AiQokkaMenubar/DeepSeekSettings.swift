import Foundation

typealias DeepSeekRefreshAction = @MainActor @Sendable () async -> Void

@MainActor
final class DeepSeekSettings: ObservableObject {
    @Published var draftKey = ""
    @Published private(set) var isConfigured = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private let credentialStore: any DeepSeekCredentialStore
    private let refresh: DeepSeekRefreshAction

    init(credentialStore: any DeepSeekCredentialStore = KeychainDeepSeekCredentialStore(), refresh: @escaping DeepSeekRefreshAction = {}) {
        self.credentialStore = credentialStore
        self.refresh = refresh
        do { isConfigured = try credentialStore.load() != nil }
        catch { errorMessage = "无法读取 DeepSeek 凭据。" }
    }

    func save() async {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { errorMessage = "请输入 DeepSeek API Key。"; return }
        isBusy = true
        defer { isBusy = false }
        do {
            try credentialStore.save(key)
            draftKey = ""
            isConfigured = true
            errorMessage = nil
            await refresh()
        } catch let error as DeepSeekCredentialError {
            errorMessage = "无法保存 DeepSeek 凭据（\(error.localizedDescription)）。"
        } catch { errorMessage = "无法保存 DeepSeek 凭据。" }
    }

    func delete() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try credentialStore.delete()
            draftKey = ""
            isConfigured = false
            errorMessage = nil
            await refresh()
        } catch let error as DeepSeekCredentialError {
            errorMessage = "无法删除 DeepSeek 凭据（\(error.localizedDescription)）。"
        } catch { errorMessage = "无法删除 DeepSeek 凭据。" }
    }
}
