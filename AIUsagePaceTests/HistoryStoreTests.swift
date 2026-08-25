import XCTest
@testable import AIUsagePace

final class HistoryStoreTests: XCTestCase {
    func testAppendAndLoadRoundTrip() async throws {
        let store = UsageHistoryStore(rootDirectory: uniqueDirectory())
        let snapshot = UsageSnapshot.stub(fingerprint: "aaa", percent: 12.5)
        try await store.append(snapshot)

        let loaded = try await store.load(fingerprint: "aaa")
        XCTAssertEqual(loaded, [snapshot])
    }

    func testAccountsAreStoredInSeparateFiles() async throws {
        let store = UsageHistoryStore(rootDirectory: uniqueDirectory())
        try await store.append(UsageSnapshot.stub(fingerprint: "aaa", percent: 1))
        try await store.append(UsageSnapshot.stub(fingerprint: "bbb", percent: 9))

        let loadedA = try await store.load(fingerprint: "aaa")
        let loadedB = try await store.load(fingerprint: "bbb")
        XCTAssertEqual(loadedA.map(\.accountFingerprint), ["aaa"])
        XCTAssertEqual(loadedB.map(\.accountFingerprint), ["bbb"])
    }

    func testTruncatedLastLineIsDropped() async throws {
        let store = UsageHistoryStore(rootDirectory: uniqueDirectory())
        let first = UsageSnapshot.stub(fingerprint: "aaa", percent: 3)
        try await store.append(first)

        let url = await store.fileURL(for: "aaa")
        var data = try Data(contentsOf: url)
        data.append(contentsOf: Array("{\"schemaVersion\":1,\"accountFinger".utf8))
        try data.write(to: url)

        let loaded = try await store.load(fingerprint: "aaa")
        XCTAssertEqual(loaded, [first])
    }

    func testRetentionKeepsSixtyDaysWhenCyclesAreShorter() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let kept = HistoryRecord(
            snapshot: UsageSnapshot.stub(
                fingerprint: "aaa",
                percent: 1,
                capturedAt: now.addingTimeInterval(-10 * 24 * 60 * 60)
            )
        )
        let dropped = HistoryRecord(
            snapshot: UsageSnapshot.stub(
                fingerprint: "aaa",
                percent: 2,
                capturedAt: now.addingTimeInterval(-61 * 24 * 60 * 60)
            )
        )

        let retained = UsageHistoryStore.retained([dropped, kept], now: now)
        XCTAssertEqual(retained.map(\.payload.capturedAt), [kept.payload.capturedAt])
    }

    private func uniqueDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AIUsagePace-history-\(UUID().uuidString)", isDirectory: true)
    }
}