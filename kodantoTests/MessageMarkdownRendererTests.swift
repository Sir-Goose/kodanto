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

    func testParsesHyphenHorizontalRule() {
        let blocks = MessageMarkdownRenderer.parseBlocks("---")

        XCTAssertEqual(blocks.count, 1)
        guard case .horizontalRule = blocks[0] else {
            return XCTFail("Expected horizontal rule.")
        }
    }

    func testParsesSpacedHyphenHorizontalRuleBeforeList() {
        let blocks = MessageMarkdownRenderer.parseBlocks("- - -")

        XCTAssertEqual(blocks.count, 1)
        guard case .horizontalRule = blocks[0] else {
            return XCTFail("Expected horizontal rule.")
        }
    }

    func testParsesAsteriskAndUnderscoreHorizontalRules() {
        for markdown in ["***", "___"] {
            let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

            XCTAssertEqual(blocks.count, 1, "Expected one block for \(markdown)")
            guard case .horizontalRule = blocks[0] else {
                return XCTFail("Expected horizontal rule for \(markdown).")
            }
        }
    }

    func testTreatsTooShortHyphenSequenceAsParagraph() {
        let blocks = MessageMarkdownRenderer.parseBlocks("--")

        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let paragraph) = blocks[0] else {
            return XCTFail("Expected paragraph.")
        }
        XCTAssertEqual(plain(paragraph), "--")
    }

    func testParsesParagraphHorizontalRuleParagraphSequence() {
        let markdown = """
        First paragraph.
        ***
        Second paragraph.
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph(let firstParagraph) = blocks[0] else {
            return XCTFail("Expected first paragraph.")
        }
        guard case .horizontalRule = blocks[1] else {
            return XCTFail("Expected horizontal rule in middle.")
        }
        guard case .paragraph(let secondParagraph) = blocks[2] else {
            return XCTFail("Expected second paragraph.")
        }

        XCTAssertEqual(plain(firstParagraph), "First paragraph.")
        XCTAssertEqual(plain(secondParagraph), "Second paragraph.")
    }

    func testIgnoresHorizontalRuleSyntaxInsideFencedCodeBlock() {
        let markdown = """
        ```md
        ---
        * * *
        ___
        ```
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("Expected code block.")
        }

        XCTAssertEqual(language, "md")
        XCTAssertTrue(code.contains("---"))
        XCTAssertTrue(code.contains("* * *"))
        XCTAssertTrue(code.contains("___"))
    }

    func testParsesSetextHeadingLevelOne() {
        let markdown = """
        Alpha Heading
        ===
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let text) = blocks[0] else {
            return XCTFail("Expected heading block.")
        }

        XCTAssertEqual(level, 1)
        XCTAssertEqual(plain(text), "Alpha Heading")
    }

    func testParsesSetextHeadingLevelTwo() {
        let markdown = """
        Beta Heading
        ---
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let text) = blocks[0] else {
            return XCTFail("Expected heading block.")
        }

        XCTAssertEqual(level, 2)
        XCTAssertEqual(plain(text), "Beta Heading")
    }

    func testPrefersSetextHeadingOverHorizontalRuleWhenPrecededByText() {
        let markdown = """
        Title
        ---
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, _) = blocks[0] else {
            return XCTFail("Expected setext heading.")
        }

        XCTAssertEqual(level, 2)
    }

    func testParsesTildeFencedCodeBlock() {
        let markdown = """
        ~~~swift
        let value = 42
        ~~~
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("Expected code block.")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let value = 42")
    }

    func testTildeFenceRequiresMatchingClosingDelimiter() {
        let markdown = """
        ~~~swift
        let value = 42
        ```
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("Expected code block.")
        }

        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("```"))
    }

    func testParsesOrderedListWithParenthesisMarker() {
        let markdown = """
        1) first
        2) second
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks[0] else {
            return XCTFail("Expected list block.")
        }

        XCTAssertEqual(items.map(\.marker), ["1.", "2."])
        XCTAssertEqual(firstParagraphText(in: items[0].blocks), "first")
        XCTAssertEqual(firstParagraphText(in: items[1].blocks), "second")
    }

    func testParsesTaskListStates() {
        let markdown = """
        - [ ] open item
        - [x] done item
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks[0] else {
            return XCTFail("Expected list block.")
        }

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].task, .unchecked)
        XCTAssertEqual(items[1].task, .checked)
        XCTAssertEqual(firstParagraphText(in: items[0].blocks), "open item")
        XCTAssertEqual(firstParagraphText(in: items[1].blocks), "done item")
    }

    func testParsesSingleLineBlockquote() {
        let blocks = MessageMarkdownRenderer.parseBlocks("> quoted")

        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let quoteBlocks) = blocks[0] else {
            return XCTFail("Expected blockquote.")
        }

        XCTAssertEqual(quoteBlocks.compactMap(paragraphText), ["quoted"])
    }

    func testParsesBlockquoteWithParagraphBreak() {
        let markdown = """
        > first
        >
        > second
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let quoteBlocks) = blocks[0] else {
            return XCTFail("Expected blockquote.")
        }

        XCTAssertEqual(quoteBlocks.compactMap(paragraphText), ["first", "second"])
    }

    func testParsesNestedBlockquote() {
        let blocks = MessageMarkdownRenderer.parseBlocks("> > deeply nested")

        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let outerBlocks) = blocks[0] else {
            return XCTFail("Expected outer blockquote.")
        }
        guard case .blockquote(let innerBlocks) = outerBlocks.first else {
            return XCTFail("Expected nested blockquote.")
        }

        XCTAssertEqual(innerBlocks.compactMap(paragraphText), ["deeply nested"])
    }

    func testParsesNestedListInsideListItem() {
        let markdown = """
        - parent
          - child
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks[0] else {
            return XCTFail("Expected top-level list.")
        }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(firstParagraphText(in: items[0].blocks), "parent")

        guard case .list(let nestedItems) = items[0].blocks.last else {
            return XCTFail("Expected nested list in list item.")
        }

        XCTAssertEqual(nestedItems.count, 1)
        XCTAssertEqual(firstParagraphText(in: nestedItems[0].blocks), "child")
    }

    func testParsesBlockquoteInsideListItem() {
        let markdown = """
        - parent
          > quoted child
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks[0] else {
            return XCTFail("Expected list.")
        }

        XCTAssertEqual(items.count, 1)
        guard case .blockquote(let quoteBlocks) = items[0].blocks.last else {
            return XCTFail("Expected blockquote inside list item.")
        }

        XCTAssertEqual(quoteBlocks.compactMap(paragraphText), ["quoted child"])
    }

    func testParsesListInsideBlockquote() {
        let blocks = MessageMarkdownRenderer.parseBlocks("> - nested")

        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let quoteBlocks) = blocks[0] else {
            return XCTFail("Expected blockquote.")
        }
        guard case .list(let listItems) = quoteBlocks.first else {
            return XCTFail("Expected list inside blockquote.")
        }

        XCTAssertEqual(listItems.count, 1)
        XCTAssertEqual(firstParagraphText(in: listItems[0].blocks), "nested")
    }

    func testParsesStandaloneIndentedCodeBlock() {
        let markdown = """
            let x = 1
            let y = 2
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0] else {
            return XCTFail("Expected indented code block.")
        }

        XCTAssertNil(language)
        XCTAssertEqual(code, "let x = 1\nlet y = 2")
    }

    func testParsesIndentedCodeBetweenParagraphs() {
        let markdown = """
        before

            code line

        after
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(paragraphText(blocks[0]), "before")

        guard case .codeBlock(let language, let code) = blocks[1] else {
            return XCTFail("Expected middle code block.")
        }

        XCTAssertNil(language)
        XCTAssertEqual(code, "code line")
        XCTAssertEqual(paragraphText(blocks[2]), "after")
    }

    func testParsesIndentedCodeInsideBlockquote() {
        let blocks = MessageMarkdownRenderer.parseBlocks(">     code")

        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let quoteBlocks) = blocks[0] else {
            return XCTFail("Expected blockquote.")
        }
        guard case .codeBlock(let language, let code) = quoteBlocks.first else {
            return XCTFail("Expected code block inside blockquote.")
        }

        XCTAssertNil(language)
        XCTAssertEqual(code, "code")
    }

    func testParsesIndentedCodeInsideListItem() {
        let markdown = """
        - parent

              nested code
        """

        let blocks = MessageMarkdownRenderer.parseBlocks(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items) = blocks[0] else {
            return XCTFail("Expected list.")
        }

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(firstParagraphText(in: items[0].blocks), "parent")

        guard case .codeBlock(let language, let code) = items[0].blocks.last else {
            return XCTFail("Expected code block inside list item.")
        }

        XCTAssertNil(language)
        XCTAssertEqual(code, "nested code")
    }

    private func paragraphText(_ block: MessageMarkdownRenderer.Block) -> String? {
        guard case .paragraph(let paragraph) = block else { return nil }
        return plain(paragraph)
    }

    private func firstParagraphText(in blocks: [MessageMarkdownRenderer.Block]) -> String? {
        blocks.compactMap(paragraphText).first
    }

    private func plain(_ attributed: AttributedString) -> String {
        String(attributed.characters)
    }

    private func plain(_ cells: [AttributedString]) -> [String] {
        cells.map(plain)
    }
}
