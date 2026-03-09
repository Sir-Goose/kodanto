import XCTest
@testable import kodanto

final class MessageMarkdownRendererTests: XCTestCase {
    func testRenderParsesMarkdownIntoDisplayText() {
        let rendered = MessageMarkdownRenderer.render("Use **bold** with `code` and a [link](https://example.com).")

        XCTAssertEqual(String(rendered.characters), "Use bold with code and a link.")
    }

    func testRenderFallsBackToPlainTextWhenParsingFails() {
        enum TestError: Error {
            case failed
        }

        let source = "```swift\nlet value = 1"
        let rendered = MessageMarkdownRenderer.render(source) { _ in
            throw TestError.failed
        }

        XCTAssertEqual(String(rendered.characters), source)
    }

    func testRenderPreservesNewlinesBetweenFormattedText() {
        let source = "**Bold text**\nRegular text"
        let rendered = MessageMarkdownRenderer.render(source)

        XCTAssertEqual(String(rendered.characters), "Bold text\nRegular text")
    }

    func testParseBlocksBuildsListItems() {
        let blocks = MessageMarkdownRenderer.parseBlocks("- one\n- two")
        let block = try? XCTUnwrap(blocks.onlyElement)

        guard let block, case .list(let items) = block else {
            return XCTFail("Expected a single list block")
        }

        XCTAssertEqual(items.map { $0.marker }, ["•", "•"])
        XCTAssertEqual(items.map { String($0.content.characters) }, ["one", "two"])
    }

    func testParseBlocksBuildsCodeFenceBlock() {
        let blocks = MessageMarkdownRenderer.parseBlocks("```swift\nlet value = 1\n```")
        let block = try? XCTUnwrap(blocks.onlyElement)

        guard let block, case .codeBlock(let language, let code) = block else {
            return XCTFail("Expected a single code block")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let value = 1")
    }

    func testParseBlocksSeparatesHeadingsParagraphsAndLists() {
        let source = "# Title\nBody line\n\n1. First\n2. Second"
        let blocks = MessageMarkdownRenderer.parseBlocks(source)

        XCTAssertEqual(blocks.count, 3)

        guard case .heading(let level, let title) = blocks[0] else {
            return XCTFail("Expected heading block")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(String(title.characters), "Title")

        guard case .paragraph(let paragraph) = blocks[1] else {
            return XCTFail("Expected paragraph block")
        }
        XCTAssertEqual(String(paragraph.characters), "Body line")

        guard case .list(let items) = blocks[2] else {
            return XCTFail("Expected list block")
        }
        XCTAssertEqual(items.map { $0.marker }, ["1.", "2."])
    }
}

private extension Array {
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}
