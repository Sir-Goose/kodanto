import XCTest
@testable import kodanto

@MainActor
final class SessionSidebarIndicatorStoreTests: XCTestCase {
    func testInitialIdleStatusShowsNoIndicator() {
        var store = SessionSidebarIndicatorStore()

        store.applyStatusMap(
            ["session-1": .idle],
            previousStatuses: [:],
            sessionIDs: ["session-1"],
            in: "/tmp/project",
            selectedSessionID: nil,
            isSelectedDirectory: false
        )

        XCTAssertEqual(store.indicator(for: "session-1", in: "/tmp/project"), .none)
    }

    func testBackgroundSessionShowsGreenAfterRunningCompletes() {
        var store = SessionSidebarIndicatorStore()
        let directory = "/tmp/project"
        let sessionID = "session-1"

        store.applyStatus(.busy, previousStatus: .idle, sessionID: sessionID, in: directory, isSelected: false)
        store.applyStatus(.idle, previousStatus: .busy, sessionID: sessionID, in: directory, isSelected: false)

        XCTAssertEqual(store.indicator(for: sessionID, in: directory), .completedUnread)
    }

    func testSelectedSessionDoesNotShowGreenWhenRunningCompletes() {
        var store = SessionSidebarIndicatorStore()
        let directory = "/tmp/project"
        let sessionID = "session-1"

        store.applyStatus(.busy, previousStatus: .idle, sessionID: sessionID, in: directory, isSelected: true)
        store.applyStatus(.idle, previousStatus: .busy, sessionID: sessionID, in: directory, isSelected: true)

        XCTAssertEqual(store.indicator(for: sessionID, in: directory), .none)
    }

    func testSelectingCompletedSessionClearsGreenIndicator() {
        var store = SessionSidebarIndicatorStore()
        let directory = "/tmp/project"
        let sessionID = "session-1"

        store.applyStatus(.busy, previousStatus: .idle, sessionID: sessionID, in: directory, isSelected: false)
        store.applyStatus(.idle, previousStatus: .busy, sessionID: sessionID, in: directory, isSelected: false)
        store.clearIndicator(for: sessionID, in: directory)

        XCTAssertEqual(store.indicator(for: sessionID, in: directory), .none)
    }
}
