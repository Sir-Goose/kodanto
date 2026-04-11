import Foundation
@testable import kodanto
import XCTest

final class PlaceholderProviderTests: XCTestCase {
    func testRandomPlaceholderReturnsValidPrompt() {
        let prompt = PlaceholderProvider.randomPlaceholder()
        XCTAssertTrue(PlaceholderProvider.prompts.contains(prompt))
    }

    func testRandomPlaceholderExcludesCurrentValue() {
        let firstPrompt = PlaceholderProvider.prompts[0]
        let result = PlaceholderProvider.randomPlaceholder(excluding: firstPrompt)
        XCTAssertNotEqual(result, firstPrompt)
    }

    func testRandomPlaceholderWithExclusionReturnsValidPrompt() {
        let excludedPrompt = PlaceholderProvider.prompts[0]
        let result = PlaceholderProvider.randomPlaceholder(excluding: excludedPrompt)
        XCTAssertTrue(PlaceholderProvider.prompts.contains(result))
        XCTAssertNotEqual(result, excludedPrompt)
    }

    func testRandomPlaceholderExcludesAllButOne() {
        for prompt in PlaceholderProvider.prompts {
            let remaining = PlaceholderProvider.prompts.filter { $0 != prompt }
            let result = PlaceholderProvider.randomPlaceholder(excluding: prompt)
            XCTAssertTrue(remaining.contains(result), "Expected \(result) to be in remaining prompts")
        }
    }

    func testPromptsArrayIsNotEmpty() {
        XCTAssertFalse(PlaceholderProvider.prompts.isEmpty)
    }

    func testPromptsArrayContainsNonEmptyStrings() {
        for prompt in PlaceholderProvider.prompts {
            XCTAssertFalse(prompt.isEmpty, "Prompts should not contain empty strings")
        }
    }
}