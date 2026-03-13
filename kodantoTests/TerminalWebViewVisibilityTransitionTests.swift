import XCTest
@testable import kodanto

final class TerminalWebViewVisibilityTransitionTests: XCTestCase {
    func testShouldRefitWhenTransitioningFromHiddenToVisible() {
        XCTAssertTrue(TerminalWebViewVisibilityTransition.shouldRefit(previous: false, current: true))
    }

    func testDoesNotRefitWhenRemainingVisible() {
        XCTAssertFalse(TerminalWebViewVisibilityTransition.shouldRefit(previous: true, current: true))
    }

    func testDoesNotRefitWhenHiding() {
        XCTAssertFalse(TerminalWebViewVisibilityTransition.shouldRefit(previous: true, current: false))
    }
}
