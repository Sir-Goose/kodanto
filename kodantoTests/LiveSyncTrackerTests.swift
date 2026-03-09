import XCTest
@testable import kodanto

@MainActor
final class LiveSyncTrackerTests: XCTestCase {
    func testStartTransitionsToConnecting() {
        var tracker = LiveSyncTracker()

        tracker.start(now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(tracker.state, .connecting)
        XCTAssertEqual(tracker.lastEventAt, Date(timeIntervalSince1970: 100))
    }

    func testReconnectTriggersRefreshOnServerConnected() {
        var tracker = LiveSyncTracker()
        tracker.start(now: Date(timeIntervalSince1970: 100))
        tracker.markReconnectNeeded(reason: "network")

        let shouldRefresh = tracker.receiveEvent(serverConnectedEvent(), now: Date(timeIntervalSince1970: 101))

        XCTAssertTrue(shouldRefresh)
        XCTAssertEqual(tracker.state, .active)
        XCTAssertEqual(tracker.reconnectCount, 1)
    }

    func testReconnectWaitsForServerConnectedBeforeRefreshing() {
        var tracker = LiveSyncTracker()
        tracker.start(now: Date(timeIntervalSince1970: 100))
        tracker.markReconnectNeeded(reason: "network")

        let heartbeatRefresh = tracker.receiveEvent(serverHeartbeatEvent(), now: Date(timeIntervalSince1970: 101))
        let connectedRefresh = tracker.receiveEvent(serverConnectedEvent(), now: Date(timeIntervalSince1970: 102))

        XCTAssertFalse(heartbeatRefresh)
        XCTAssertTrue(connectedRefresh)
    }

    func testHeartbeatTimeoutUsesConfiguredThreshold() {
        var tracker = LiveSyncTracker()
        tracker.start(now: Date(timeIntervalSince1970: 100))

        XCTAssertFalse(tracker.isHeartbeatTimedOut(now: Date(timeIntervalSince1970: 114.9)))
        XCTAssertTrue(tracker.isHeartbeatTimedOut(now: Date(timeIntervalSince1970: 115.1)))
    }
}

private func serverConnectedEvent() -> OpenCodeGlobalEvent {
    OpenCodeGlobalEvent(directory: nil, payload: .serverConnected)
}

private func serverHeartbeatEvent() -> OpenCodeGlobalEvent {
    OpenCodeGlobalEvent(directory: nil, payload: .serverHeartbeat)
}
