import XCTest
@testable import kodanto

final class TerminalPanelSizingTests: XCTestCase {
    func testClampedHeightUsesMinimumWhenPreferredTooSmall() {
        let height = TerminalPanelSizing.clampedHeight(preferredHeight: 80, availableHeight: 600, minimumHeight: 140)
        XCTAssertEqual(height, 140)
    }

    func testClampedHeightUsesMaximumWhenPreferredTooLarge() {
        let height = TerminalPanelSizing.clampedHeight(preferredHeight: 700, availableHeight: 500, minimumHeight: 140)
        XCTAssertEqual(height, 300)
    }

    func testClampedHeightUsesPreferredInsideBounds() {
        let height = TerminalPanelSizing.clampedHeight(preferredHeight: 240, availableHeight: 700, minimumHeight: 140)
        XCTAssertEqual(height, 240)
    }
}
