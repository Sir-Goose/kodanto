import XCTest
@testable import kodanto

final class SessionTodoPresentationTests: XCTestCase {
    func testStatusParsingIncludesFallbackForUnknownValues() {
        XCTAssertEqual(SessionTodoStatus(rawStatus: "pending"), .pending)
        XCTAssertEqual(SessionTodoStatus(rawStatus: "in_progress"), .inProgress)
        XCTAssertEqual(SessionTodoStatus(rawStatus: "completed"), .completed)
        XCTAssertEqual(SessionTodoStatus(rawStatus: "cancelled"), .cancelled)
        XCTAssertEqual(SessionTodoStatus(rawStatus: "unexpected"), .unknown)
    }

    func testCompletedCountAndAllClosedTreatCancelledAsClosedButNotCompleted() {
        let mixed = [
            todo("Completed", status: "completed"),
            todo("Cancelled", status: "cancelled"),
            todo("Pending", status: "pending")
        ]
        XCTAssertEqual(SessionTodoPresentation.completedCount(in: mixed), 1)
        XCTAssertFalse(SessionTodoPresentation.allClosed(in: mixed))

        let closedOnly = [
            todo("Completed", status: "completed"),
            todo("Cancelled", status: "cancelled")
        ]
        XCTAssertEqual(SessionTodoPresentation.completedCount(in: closedOnly), 1)
        XCTAssertTrue(SessionTodoPresentation.allClosed(in: closedOnly))
        XCTAssertFalse(SessionTodoPresentation.allClosed(in: []))
    }

    func testPreviewSelectionUsesExpectedPrecedence() {
        let withInProgress = [
            todo("Pending first", status: "pending"),
            todo("In progress", status: "in_progress"),
            todo("Completed", status: "completed")
        ]
        XCTAssertEqual(SessionTodoPresentation.previewTodo(in: withInProgress)?.content, "In progress")

        let withPendingOnly = [
            todo("Pending first", status: "pending"),
            todo("Pending second", status: "pending"),
            todo("Completed", status: "completed")
        ]
        XCTAssertEqual(SessionTodoPresentation.previewTodo(in: withPendingOnly)?.content, "Pending first")

        let withCompletedOnly = [
            todo("Completed first", status: "completed"),
            todo("Cancelled", status: "cancelled"),
            todo("Completed last", status: "completed")
        ]
        XCTAssertEqual(SessionTodoPresentation.previewTodo(in: withCompletedOnly)?.content, "Completed last")

        let fallback = [
            todo("Cancelled first", status: "cancelled"),
            todo("Cancelled second", status: "cancelled")
        ]
        XCTAssertEqual(SessionTodoPresentation.previewTodo(in: fallback)?.content, "Cancelled first")
    }

    func testDockTransitionShowsFromHiddenWhenTodosAppear() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .hidden,
            event: .todosChanged([todo("Start", status: "pending")])
        )

        XCTAssertEqual(transition.state, .visible)
        XCTAssertEqual(transition.effect, .none)
    }

    func testDockTransitionStaysHiddenWhenAllTodosAreClosedFromHiddenState() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .hidden,
            event: .todosChanged([
                todo("Done", status: "completed"),
                todo("Cancelled", status: "cancelled")
            ])
        )

        XCTAssertEqual(transition.state, .hidden)
        XCTAssertEqual(transition.effect, .none)
    }

    func testDockTransitionClosesAfterAllTodosAreClosed() {
        let closing = SessionTodoDockStateMachine.reduce(
            state: .visible,
            event: .todosChanged([todo("Done", status: "completed")])
        )
        XCTAssertEqual(closing.state, .closing)
        XCTAssertEqual(closing.effect, .startCloseTimer(SessionTodoDockStateMachine.closeDelay))

        let hidden = SessionTodoDockStateMachine.reduce(
            state: closing.state,
            event: .closeTimerFired
        )
        XCTAssertEqual(hidden.state, .hidden)
        XCTAssertEqual(hidden.effect, .none)
    }

    func testDockTransitionCancelsCloseWhenActiveTodoReappears() {
        let transition = SessionTodoDockStateMachine.reduce(
            state: .closing,
            event: .todosChanged([todo("Back to work", status: "in_progress")])
        )

        XCTAssertEqual(transition.state, .visible)
        XCTAssertEqual(transition.effect, .cancelCloseTimer)
    }

    private func todo(_ content: String, status: String) -> OpenCodeTodo {
        OpenCodeTodo(content: content, status: status, priority: "medium")
    }
}
