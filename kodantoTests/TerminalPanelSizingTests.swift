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

    func testDraggedHeightTracksUpwardMovementOneToOne() {
        let height = TerminalPanelSizing.draggedHeight(
            startHeight: 240,
            startMouseY: 500,
            currentMouseY: 460,
            availableHeight: 700,
            minimumHeight: 140
        )
        XCTAssertEqual(height, 280)
    }

    func testDraggedHeightTracksDownwardMovementOneToOne() {
        let height = TerminalPanelSizing.draggedHeight(
            startHeight: 240,
            startMouseY: 500,
            currentMouseY: 560,
            availableHeight: 700,
            minimumHeight: 140
        )
        XCTAssertEqual(height, 180)
    }

    func testDraggedHeightClampsToMinimum() {
        let height = TerminalPanelSizing.draggedHeight(
            startHeight: 140,
            startMouseY: 500,
            currentMouseY: 850,
            availableHeight: 700,
            minimumHeight: 140
        )
        XCTAssertEqual(height, 140)
    }

    func testDraggedHeightClampsToMaximum() {
        let height = TerminalPanelSizing.draggedHeight(
            startHeight: 260,
            startMouseY: 500,
            currentMouseY: 250,
            availableHeight: 500,
            minimumHeight: 140
        )
        XCTAssertEqual(height, 300)
    }
}
