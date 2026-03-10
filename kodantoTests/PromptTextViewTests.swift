import AppKit
import XCTest
@testable import kodanto

@MainActor
final class PromptTextViewTests: XCTestCase {
    private let returnKeyCode: UInt16 = 36
    private let keypadEnterKeyCode: UInt16 = 76
    private let letterAKeyCode: UInt16 = 0

    func testShouldSubmitForPlainReturn() {
        XCTAssertTrue(PromptTextView.shouldSubmit(for: returnKeyCode, modifierFlags: []))
    }

    func testShouldSubmitForPlainKeypadEnter() {
        XCTAssertTrue(PromptTextView.shouldSubmit(for: keypadEnterKeyCode, modifierFlags: [.numericPad]))
    }

    func testShouldSubmitForCommandReturn() {
        XCTAssertTrue(PromptTextView.shouldSubmit(for: returnKeyCode, modifierFlags: [.command]))
    }

    func testShouldSubmitForCommandKeypadEnter() {
        XCTAssertTrue(PromptTextView.shouldSubmit(for: keypadEnterKeyCode, modifierFlags: [.command, .numericPad]))
    }

    func testDoesNotSubmitForShiftReturn() {
        XCTAssertFalse(PromptTextView.shouldSubmit(for: returnKeyCode, modifierFlags: [.shift]))
    }

    func testDoesNotSubmitForShiftKeypadEnter() {
        XCTAssertFalse(PromptTextView.shouldSubmit(for: keypadEnterKeyCode, modifierFlags: [.shift, .numericPad]))
    }

    func testDoesNotSubmitForOtherKeys() {
        XCTAssertFalse(PromptTextView.shouldSubmit(for: letterAKeyCode, modifierFlags: []))
    }

    func testDoesNotSubmitForAdditionalModifiers() {
        XCTAssertFalse(PromptTextView.shouldSubmit(for: returnKeyCode, modifierFlags: [.command, .shift]))
        XCTAssertFalse(PromptTextView.shouldSubmit(for: returnKeyCode, modifierFlags: [.option]))
    }
}
