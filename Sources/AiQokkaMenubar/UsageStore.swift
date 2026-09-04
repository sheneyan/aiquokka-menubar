import Foundation
import Combine

typealias UsageSnapshotLoader = @Sendable () async throws -> UsageSnapshot
typealias UsageSleeper = @Sendable (Duration) async throws -> Void
typealias UsageSnapshotHandler = @MainActor (UsageSnapshot) async -> Void

@MainActor
final class UsageStore: ObservableObject {
    static let refreshInterval: Duration = .seconds(60)

    private let loader: UsageSnapshotLoader
    private let sleep: UsageSleeper
    private let didLoadSnapshot: UsageSnapshotHandler?
    private var autoRefreshTask: Task<Void, Never>?

    @Published var snapshot: UsageSnapshot?
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var lastError: String?

    init(
        loader: @escaping UsageSnapshotLoader,
        sleep: @escaping UsageSleeper = { duration in
            try await Task.sleep(for: duration)
        },
        didLoadSnapshot: UsageSnapshotHandler? = nil
    ) {
        self.loader = loader
        self.sleep = sleep
        self.didLoadSnapshot = didLoadSnapshot
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let nextSnapshot = try await loader()
            snapshot = nextSnapshot
            lastUpdated = nextSnapshot.fetchedAt
            if let didLoadSnapshot {
                await didLoadSnapshot(nextSnapshot)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()

            while !Task.isCancelled {
                do {
                    try await self.sleep(Self.refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
