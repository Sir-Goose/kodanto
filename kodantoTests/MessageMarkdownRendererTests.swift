import XCTest
@testable import kodanto

final class MessageMarkdownRendererTests: XCTestCase {
    func testParsesValidGFMTable() {
        let markdown = """
        | Name | Role |
        | --- | --- |
        | Ada | Engineer |
        | Linus | Maintainer |
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("Expected a table block.")
        }

        XCTAssertEqual(plain(table.headers), ["Name", "Role"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(plain(table.rows[0]), ["Ada", "Engineer"])
        XCTAssertEqual(plain(table.rows[1]), ["Linus", "Maintainer"])
    }

    func testParsesTableAlignmentMarkers() {
        let markdown = """
        | Left | Center | Right |
        | :--- | :----: | ----: |
        | A | B | C |
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("Expected a table block.")
        }

        XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
    }

    func testFallsBackToParagraphWhenDividerRowIsInvalid() {
        let markdown = """
        | Name | Role |
        | -- | --- |
        | Ada | Engineer |
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let paragraph) = blocks[0] else {
            return XCTFail("Expected paragraph fallback for invalid divider row.")
        }

        let rendered = plain(paragraph)
        XCTAssertTrue(rendered.contains("| Name | Role |"))
        XCTAssertTrue(rendered.contains("| -- | --- |"))
    }

    func testTableStopsAtBlankLineAndThenParsesFollowingParagraph() {
        let markdown = """
        | Name | Role |
        | --- | --- |
        | Ada | Engineer |

        Following paragraph.
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 2)
        guard case .table = blocks[0] else {
            return XCTFail("Expected first block to be table.")
        }
        guard case .paragraph(let paragraph) = blocks[1] else {
            return XCTFail("Expected second block to be paragraph.")
        }
        XCTAssertEqual(plain(paragraph), "Following paragraph.")
    }

    func testIgnoresTableSyntaxInsideFencedCodeBlock() {
        let markdown = """
        ```md
        | Name | Role |
        | --- | --- |
        | Ada | Engineer |
        ```
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("Expected code block.")
        }

        XCTAssertEqual(language, "md")
        XCTAssertTrue(code.contains("| Name | Role |"))
    }

    func testParsesEscapedPipeInsideTableCell() {
        let markdown = """
        | Name | Notes |
        | --- | --- |
        | Ada | left\\|right |
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .table(let table) = blocks[0] else {
            return XCTFail("Expected a table block.")
        }

        XCTAssertEqual(plain(table.rows[0]), ["Ada", "left|right"])
    }

    private func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    private func plain(_ cells: [AttributedString]) -> [String] {
        cells.map(plain)
    }
}
