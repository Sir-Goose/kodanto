import AppKit
import XCTest
@testable import kodanto

final class TerminalToggleButtonStyleTests: XCTestCase {
    func testOffStateUsesFilledSymbolWithHighContrastLabelColor() {
        let style = TerminalToggleButtonStyle.resolve(isOpen: false, isEnabled: true)

        XCTAssertEqual(style.symbolName, "rectangle.bottomthird.inset.filled")
        XCTAssertTrue(style.foreground.isEqual(NSColor.labelColor))
    }

    func testOpenStateUsesAccentColor() {
        let style = TerminalToggleButtonStyle.resolve(isOpen: true, isEnabled: true)

        XCTAssertEqual(style.symbolName, "rectangle.bottomthird.inset.filled")
        XCTAssertTrue(style.foreground.isEqual(NSColor.controlAccentColor))
    }

    func testDisabledStateUsesTertiaryLabelColor() {
        let style = TerminalToggleButtonStyle.resolve(isOpen: false, isEnabled: false)

        XCTAssertEqual(style.symbolName, "rectangle.bottomthird.inset.filled")
        XCTAssertTrue(style.foreground.isEqual(NSColor.tertiaryLabelColor))
    }
}
