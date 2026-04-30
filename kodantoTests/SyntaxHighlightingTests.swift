@testable import kodanto
import XCTest

@MainActor
final class SyntaxHighlightingTests: XCTestCase {
    func testSharedInstanceIsNotNil() {
        let service = SyntaxHighlighterService.shared
        XCTAssertNotNil(service)
    }

    func testHighlightSwiftCodeReturnsAttributedString() {
        let code = "func hello() -> String { return \"world\" }"
        let result = SyntaxHighlighterService.shared.highlight(code, as: "swift")
        XCTAssertNotNil(result)
    }

    func testHighlightSwiftCodeProducedMultipleRuns() {
        let code = "func hello() -> String { return \"world\" }"
        guard let result = SyntaxHighlighterService.shared.highlight(code, as: "swift") else {
            XCTFail("Expected non-nil AttributedString")
            return
        }
        let runCount = result.runs.count
        XCTAssertGreaterThan(runCount, 1, "Expected highlighting to produce multiple attribute runs (got \(runCount))")
    }

    func testHighlightPythonCodeReturnsAttributedString() {
        let code = "def hello():\n    return \"world\""
        let result = SyntaxHighlighterService.shared.highlight(code, as: "python")
        XCTAssertNotNil(result)
    }

    func testHighlightJavaScriptCodeReturnsAttributedString() {
        let code = "function hello() { return \"world\"; }"
        let result = SyntaxHighlighterService.shared.highlight(code, as: "javascript")
        XCTAssertNotNil(result)
    }

    func testHighlightShellCodeReturnsAttributedString() {
        let code = "for f in *.swift; do echo \"$f\"; done"
        let result = SyntaxHighlighterService.shared.highlight(code, as: "shell")
        XCTAssertNotNil(result)
    }

    func testHighlightJSONReturnsAttributedString() {
        let code = "{\"name\": \"test\", \"count\": 42}"
        let result = SyntaxHighlighterService.shared.highlight(code, as: "json")
        XCTAssertNotNil(result)
    }

    func testHighlightWithAutoDetectReturnsAttributedString() {
        let code = "let x = 42"
        let result = SyntaxHighlighterService.shared.highlight(code, as: nil)
        XCTAssertNotNil(result)
    }

    func testHighlightEmptyCodeReturnsEmptyAttributedString() {
        let result = SyntaxHighlighterService.shared.highlight("", as: "swift")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.characters.count, 0)
    }

    func testHighlightGarbageCodeStillReturnsResult() {
        let code = "???!!!___123"
        let result = SyntaxHighlighterService.shared.highlight(code, as: "swift")
        XCTAssertNotNil(result)
    }
}
