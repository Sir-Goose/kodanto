import XCTest
@testable import kodanto

@MainActor
final class LiveSyncTrackerTests: XCTestCase {
    func testStartTransitionsToConnectingAndTracksTimestamp() {
        var tracker = LiveSyncTracker()
        let now = Date(timeIntervalSince1970: 100)

        tracker.start(now: now)

        XCTAssertEqual(tracker.state, .connecting)
        XCTAssertEqual(tracker.lastEventAt, now)
        XCTAssertEqual(tracker.reconnectCount, 0)
    }

    func testStartKeepsReconnectingStateDuringRetryLoop() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "network error")

        tracker.start(now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(tracker.state, .reconnecting("network error"))
        XCTAssertEqual(tracker.reconnectCount, 1)
    }

    func testReceiveServerConnectedAfterReconnectRequestsRefresh() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "stream ended")

        let shouldRefresh = tracker.receiveEvent(
            TestFixtures.globalEvent(payload: .serverConnected),
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(shouldRefresh)
        XCTAssertEqual(tracker.state, .active)
    }

    func testReceiveNonServerConnectedEventAfterReconnectDoesNotRequestRefresh() {
        var tracker = LiveSyncTracker()
        tracker.markReconnectNeeded(reason: "stream ended")

        let shouldRefresh = tracker.receiveEvent(
            TestFixtures.globalEvent(payload: .serverHeartbeat),
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertFalse(shouldRefresh)
        XCTAssertEqual(tracker.state, .active)
    }

    func testHeartbeatTimeoutUsesMostRecentEventTimestamp() {
        var tracker = LiveSyncTracker()
        let now = Date(timeIntervalSince1970: 1_000)
        tracker.start(now: now)

        XCTAssertFalse(tracker.isHeartbeatTimedOut(now: now.addingTimeInterval(LiveSyncTracker.heartbeatTimeout - 0.1)))
        XCTAssertTrue(tracker.isHeartbeatTimedOut(now: now.addingTimeInterval(LiveSyncTracker.heartbeatTimeout + 0.1)))
    }

    func testStopResetsRuntimeState() {
        var tracker = LiveSyncTracker()
        tracker.start(now: Date(timeIntervalSince1970: 100))
        _ = tracker.receiveEvent(TestFixtures.globalEvent(payload: .serverConnected), now: Date(timeIntervalSince1970: 101))

        tracker.stop()

        XCTAssertEqual(tracker.state, .inactive)
        XCTAssertEqual(tracker.lastEventAt, .distantPast)
        XCTAssertFalse(tracker.isHeartbeatTimedOut(now: Date(timeIntervalSince1970: 200)))
    }
}
