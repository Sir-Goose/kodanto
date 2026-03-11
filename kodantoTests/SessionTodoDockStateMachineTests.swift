import XCTest
@testable import kodanto

@MainActor
final class SessionTodoDockStateMachineTests: XCTestCase {
    func testOpenTodosRevealDock() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .hidden,
            event: .todosChanged([TestFixtures.todo("Run tests", status: "pending")])
        )

        XCTAssertEqual(transition.state, .visible)
        XCTAssertEqual(transition.effect, .none)
    }

    func testClosedTodosStartCloseTimerWhenDockIsVisible() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .visible,
            event: .todosChanged([TestFixtures.todo("Run tests", status: "completed")])
        )

        XCTAssertEqual(transition.state, .closing)
        XCTAssertEqual(transition.effect, .startCloseTimer(SessionTodoDockStateMachine.closeDelay))
    }

    func testCloseTimerHidesDockWhileClosing() {
        let transition = SessionTodoDockStateMachine.reduce(state: .closing, event: .closeTimerFired)

        XCTAssertEqual(transition.state, .hidden)
        XCTAssertEqual(transition.effect, .none)
    }

    func testReopenedTodosCancelPendingCloseTimer() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .closing,
            event: .todosChanged([TestFixtures.todo("Run tests", status: "in_progress")])
        )

        XCTAssertEqual(transition.state, .visible)
        XCTAssertEqual(transition.effect, .cancelCloseTimer)
    }

    func testAlreadyClosedTodosStayHiddenWhenDockHasNotOpenedYet() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .hidden,
            event: .todosChanged([TestFixtures.todo("Run tests", status: "completed")])
        )

        XCTAssertEqual(transition.state, .hidden)
        XCTAssertEqual(transition.effect, .none)
    }
}
