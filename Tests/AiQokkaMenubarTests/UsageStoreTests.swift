@testable import AiQokkaMenubar
import Foundation
import XCTest

@MainActor
final class UsageStoreTests: XCTestCase {
    func testInitialStateIsIdleWithoutData() {
        let store = UsageStore(loader: { fatalError("loader should not run") })

        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.lastUpdated)
        XCTAssertNil(store.lastError)
    }

    func testRefreshSuccessStoresSnapshotAndTimestamp() async {
        let fetchedAt = Date(timeIntervalSince1970: 123)
        let snapshot = UsageSnapshot(providers: [], fetchedAt: fetchedAt)
        let store = UsageStore(loader: { snapshot })

        await store.refresh()

        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(store.lastUpdated, fetchedAt)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.lastError)
    }

    func testRefreshSuccessInvokesSnapshotCallback() async {
        let recorder = SnapshotRecorder()
        let snapshot = UsageSnapshot(providers: [], fetchedAt: Date(timeIntervalSince1970: 123))
        let store = UsageStore(
            loader: { snapshot },
            didLoadSnapshot: { value in
                await recorder.record(value)
            }
        )

        await store.refresh()

        let values = await recorder.values()
        XCTAssertEqual(values, [snapshot])
    }

    func testFailureKeepsPreviousSnapshotAndReportsError() async {
        let previous = UsageSnapshot(providers: [], fetchedAt: Date(timeIntervalSince1970: 1))
        let loader = ResultLoader(results: [
            .success(previous),
            .failure(StoreTestError.network)
        ])
        let store = UsageStore(loader: { try await loader.next() })

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.snapshot, previous)
        XCTAssertEqual(store.lastUpdated, previous.fetchedAt)
        XCTAssertEqual(store.lastError, "network error")
        XCTAssertFalse(store.isRefreshing)
    }

    func testFailureWithoutPreviousSnapshotReportsError() async {
        let store = UsageStore(loader: { throw StoreTestError.notConfigured })

        await store.refresh()

        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isRefreshing)
    }

    func testRefreshFailureDoesNotInvokeSnapshotCallback() async {
        let recorder = SnapshotRecorder()
        let store = UsageStore(
            loader: { throw StoreTestError.network },
            didLoadSnapshot: { value in
                await recorder.record(value)
            }
        )

        await store.refresh()

        let values = await recorder.values()
        XCTAssertTrue(values.isEmpty)
    }

    func testOverlappingRefreshesOnlyInvokeLoaderOnce() async {
        let gate = AsyncGate()
        let calls = CallCounter()
        let snapshot = UsageSnapshot(providers: [], fetchedAt: Date())
        let store = UsageStore(loader: {
            await calls.increment()
            await gate.wait()
            return snapshot
        })

        let firstRefresh = Task { await store.refresh() }
        await calls.waitUntil(atLeast: 1)
        await store.refresh()

        let callCount = await calls.currentValue()
        XCTAssertEqual(callCount, 1)
        await gate.open()
        await firstRefresh.value
        XCTAssertEqual(store.snapshot, snapshot)
    }

    func testRefreshIntervalIsSixtySecondsAndSchedulerUsesIt() async {
        let intervals = IntervalRecorder()
        let snapshot = UsageSnapshot(providers: [], fetchedAt: Date())
        let store = UsageStore(
            loader: { snapshot },
            sleep: { duration in
                await intervals.record(duration)
                throw CancellationError()
            }
        )

        XCTAssertEqual(UsageStore.refreshInterval, .seconds(60))
        store.startAutoRefresh()
        await intervals.waitUntilRecorded()

        let recordedIntervals = await intervals.currentValues()
        XCTAssertEqual(recordedIntervals, [.seconds(60)])
        store.stopAutoRefresh()
    }
}

private enum StoreTestError: Error, LocalizedError {
    case network
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .network:
            return "network error"
        case .notConfigured:
            return "not configured"
        }
    }
}

private actor ResultLoader {
    private var results: [Result<UsageSnapshot, Error>]

    init(results: [Result<UsageSnapshot, Error>]) {
        self.results = results
    }

    func next() throws -> UsageSnapshot {
        try results.removeFirst().get()
    }
}

private actor SnapshotRecorder {
    private var recorded: [UsageSnapshot] = []

    func record(_ snapshot: UsageSnapshot) {
        recorded.append(snapshot)
    }

    func values() -> [UsageSnapshot] {
        recorded
    }
}

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }

    func waitUntil(atLeast expected: Int) async {
        while value < expected {
            await Task.yield()
        }
    }

    func currentValue() -> Int {
        value
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor IntervalRecorder {
    private(set) var values: [Duration] = []

    func record(_ value: Duration) {
        values.append(value)
    }

    func waitUntilRecorded() async {
        while values.isEmpty {
            await Task.yield()
        }
    }

    func currentValues() -> [Duration] {
        values
    }
}
