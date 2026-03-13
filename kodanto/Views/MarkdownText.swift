import Foundation
import SwiftUI

struct MarkdownText: View, Equatable {
    let text: String

    var body: some View {
        let blocks = MessageMarkdownRenderer.parseBlocks(text)
        MarkdownBlocksStack(blocks: blocks, spacing: 12)
    }
}

enum MessageMarkdownRenderer {
    private final class CachedBlocks: NSObject {
        let blocks: [Block]

        init(blocks: [Block]) {
            self.blocks = blocks
        }
    }

    indirect enum Block: Equatable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        case horizontalRule
        case list(items: [ListItem])
        case blockquote([Block])
        case codeBlock(language: String?, code: String)
        case table(TableData)
    }

    struct ListItem: Equatable {
        let marker: String
        let task: TaskState?
        let blocks: [Block]
    }

    enum TaskState: Equatable {
        case unchecked
        case checked
    }

    enum TableColumnAlignment: Equatable {
        case leading
        case center
        case trailing
    }

    struct TableData: Equatable {
        let headers: [AttributedString]
        let rows: [[AttributedString]]
        let alignments: [TableColumnAlignment]
    }

    static func render(_ text: String) -> AttributedString {
        guard let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return AttributedString(text)
        }

        return attributed
    }

    static func parseBlocks(_ text: String) -> [Block] {
        let key = text as NSString
        if let cached = blockCache.object(forKey: key) {
            return cached.blocks
        }

        let blocks = parseBlocksUncached(text)
        blockCache.setObject(CachedBlocks(blocks: blocks), forKey: key, cost: key.length)
        return blocks
    }

    private static let blockCache: NSCache<NSString, CachedBlocks> = {
        let cache = NSCache<NSString, CachedBlocks>()
        cache.countLimit = 512
        cache.totalCostLimit = 4_000_000
        return cache
    }()

    private static func parseBlocksUncached(_ text: String) -> [Block] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let blocks = parseBlocks(from: lines)

        if blocks.isEmpty, !text.isEmpty {
            return [.paragraph(AttributedString(text))]
        }

        return blocks
    }

    private enum PendingListKind: Equatable {
        case unordered
        case ordered
    }

    private struct ParsedListItem {
        let kind: PendingListKind
        let marker: String
        let task: TaskState?
        let content: String
        let indent: Int
    }

    private struct ParsedList {
        let items: [ListItem]
        let linesConsumed: Int
    }

    private struct ParsedBlockquote {
        let blocks: [Block]
        let linesConsumed: Int
    }

    private struct PendingCodeFence {
        let marker: Character
        let length: Int
        let language: String?
    }

    private struct ParsedIndentedCodeBlock {
        let code: String
        let linesConsumed: Int
    }

    private struct Heading {
        let level: Int
        let text: String
    }

    private struct SetextHeading {
        let level: Int
        let text: String
    }

    private struct ParsedTable {
        let data: TableData
        let linesConsumed: Int
    }

    private static func parseBlocks(from lines: [String]) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.joined(separator: "\n")
            if !paragraph.isEmpty {
                blocks.append(.paragraph(render(paragraph)))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if let openingFence = openingCodeFence(from: line) {
                flushParagraph()

                var codeLines: [String] = []
                var fenceIndex = index + 1
                var didCloseFence = false

                while fenceIndex < lines.count {
                    if isClosingCodeFence(lines[fenceIndex], matching: openingFence) {
                        didCloseFence = true
                        break
                    }
                    codeLines.append(lines[fenceIndex])
                    fenceIndex += 1
                }

                blocks.append(.codeBlock(language: openingFence.language, code: codeLines.joined(separator: "\n")))
                index = didCloseFence ? (fenceIndex + 1) : lines.count
                continue
            }

            if let quote = parseBlockquote(at: index, lines: lines) {
                flushParagraph()
                blocks.append(.blockquote(quote.blocks))
                index += quote.linesConsumed
                continue
            }

            if let table = parseTable(at: index, lines: lines) {
                flushParagraph()
                blocks.append(.table(table.data))
                index += table.linesConsumed
                continue
            }

            if let setext = parseSetextHeading(at: index, lines: lines) {
                flushParagraph()
                blocks.append(.heading(level: setext.level, text: render(setext.text)))
                index += 2
                continue
            }

            if let heading = parseHeading(from: line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: render(heading.text)))
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                flushParagraph()
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if let list = parseList(at: index, lines: lines) {
                flushParagraph()
                blocks.append(.list(items: list.items))
                index += list.linesConsumed
                continue
            }

            if let indentedCode = parseIndentedCodeBlock(at: index, lines: lines) {
                flushParagraph()
                blocks.append(.codeBlock(language: nil, code: indentedCode.code))
                index += indentedCode.linesConsumed
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func parseSetextHeading(at startIndex: Int, lines: [String]) -> SetextHeading? {
        guard startIndex + 1 < lines.count else { return nil }

        let titleLine = lines[startIndex]
        let underlineLine = lines[startIndex + 1]

        let titleTrimmed = titleLine.trimmingCharacters(in: .whitespaces)
        guard !titleTrimmed.isEmpty else { return nil }
        guard countLeadingIndent(titleLine) < 4 else { return nil }
        guard parseListItem(from: titleLine) == nil else { return nil }
        guard parseHeading(from: titleLine) == nil else { return nil }
        guard openingCodeFence(from: titleLine) == nil else { return nil }
        guard !isBlockquoteLine(titleLine) else { return nil }

        guard let level = parseSetextUnderlineLevel(underlineLine) else { return nil }
        return SetextHeading(level: level, text: titleTrimmed)
    }

    private static func parseSetextUnderlineLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return nil }

        if compact.allSatisfy({ $0 == "=" }) {
            return 1
        }
        if compact.allSatisfy({ $0 == "-" }) {
            return 2
        }

        return nil
    }

    private static func parseHeading(from line: String) -> Heading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }

        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }

        return Heading(level: hashes.count, text: String(remainder.dropFirst()))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }

        return compact.allSatisfy { $0 == marker }
    }

    private static func parseList(at startIndex: Int, lines: [String]) -> ParsedList? {
        guard let firstItem = parseListItem(from: lines[startIndex]) else { return nil }

        let listIndent = firstItem.indent
        let listKind = firstItem.kind

        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            guard let itemStart = parseListItem(from: lines[index]),
                  itemStart.indent == listIndent,
                  itemStart.kind == listKind else {
                break
            }

            var itemLines: [String] = [itemStart.content]
            index += 1

            while index < lines.count {
                let line = lines[index]

                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    itemLines.append("")
                    index += 1
                    continue
                }

                if let nextItem = parseListItem(from: line),
                   nextItem.indent == listIndent,
                   nextItem.kind == listKind {
                    break
                }

                let indent = countLeadingIndent(line)
                if indent <= listIndent, !isBlockquoteLine(line) {
                    break
                }

                let stripped = stripLeadingIndent(line, count: min(indent, listIndent + 2))
                itemLines.append(stripped)
                index += 1
            }

            let normalizedItemLines = trimOuterBlankLines(itemLines)
            let parsedItemBlocks = parseBlocks(from: normalizedItemLines)
            let blocksForItem: [Block]

            if parsedItemBlocks.isEmpty {
                if itemStart.content.isEmpty {
                    blocksForItem = []
                } else {
                    blocksForItem = [.paragraph(render(itemStart.content))]
                }
            } else {
                blocksForItem = parsedItemBlocks
            }

            items.append(ListItem(marker: itemStart.marker, task: itemStart.task, blocks: blocksForItem))
        }

        guard !items.isEmpty else { return nil }
        return ParsedList(items: items, linesConsumed: index - startIndex)
    }

    private static func parseListItem(from line: String) -> ParsedListItem? {
        let indent = countLeadingIndent(line)
        guard indent < 4 else { return nil }

        let trimmed = stripLeadingIndent(line, count: indent)

        for marker in ["-", "*", "+"] {
            if trimmed.hasPrefix("\(marker) ") {
                let rawContent = String(trimmed.dropFirst(2))
                let (taskState, content) = parseTaskState(from: rawContent)
                return ParsedListItem(
                    kind: .unordered,
                    marker: "•",
                    task: taskState,
                    content: content,
                    indent: indent
                )
            }
        }

        let digits = trimmed.prefix { $0.wholeNumberValue != nil }
        guard !digits.isEmpty else { return nil }

        let remainder = trimmed.dropFirst(digits.count)
        guard let delimiter = remainder.first, delimiter == "." || delimiter == ")" else { return nil }
        guard remainder.dropFirst().first == " " else { return nil }

        let rawContent = String(remainder.dropFirst(2))
        let (taskState, content) = parseTaskState(from: rawContent)

        return ParsedListItem(
            kind: .ordered,
            marker: "\(digits).",
            task: taskState,
            content: content,
            indent: indent
        )
    }

    private static func parseTaskState(from content: String) -> (TaskState?, String) {
        let chars = Array(content)
        guard chars.count >= 4 else { return (nil, content) }
        guard chars[0] == "[", chars[2] == "]" else { return (nil, content) }

        let stateMarker = chars[1]
        guard stateMarker == " " || stateMarker == "x" || stateMarker == "X" else { return (nil, content) }
        guard chars[3] == " " || chars[3] == "\t" else { return (nil, content) }

        let state: TaskState = stateMarker == " " ? .unchecked : .checked
        return (state, String(chars.dropFirst(4)))
    }

    private static func parseBlockquote(at startIndex: Int, lines: [String]) -> ParsedBlockquote? {
        guard isBlockquoteLine(lines[startIndex]) else { return nil }

        var quotedLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]

            if let stripped = stripBlockquotePrefix(from: line) {
                quotedLines.append(stripped)
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var probe = index + 1
                var hasFutureQuoteLine = false

                while probe < lines.count {
                    let candidate = lines[probe]
                    if candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        probe += 1
                        continue
                    }
                    hasFutureQuoteLine = stripBlockquotePrefix(from: candidate) != nil
                    break
                }

                if hasFutureQuoteLine {
                    quotedLines.append("")
                    index += 1
                    continue
                }
            }

            break
        }

        let normalizedQuotedLines = trimOuterBlankLines(quotedLines)
        let blocks = parseBlocks(from: normalizedQuotedLines)
        return ParsedBlockquote(blocks: blocks, linesConsumed: index - startIndex)
    }

    private static func isBlockquoteLine(_ line: String) -> Bool {
        stripBlockquotePrefix(from: line) != nil
    }

    private static func stripBlockquotePrefix(from line: String) -> String? {
        var index = line.startIndex
        var leading = 0

        while index < line.endIndex, leading < 3, line[index] == " " {
            index = line.index(after: index)
            leading += 1
        }

        guard index < line.endIndex, line[index] == ">" else { return nil }
        index = line.index(after: index)

        if index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
        }

        return String(line[index...])
    }

    private static func openingCodeFence(from line: String) -> PendingCodeFence? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }

        let markerCount = trimmed.prefix { $0 == first }.count
        guard markerCount >= 3 else { return nil }

        let remainder = trimmed.dropFirst(markerCount)
        let language = remainder
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)

        return PendingCodeFence(marker: first, length: markerCount, language: language)
    }

    private static func isClosingCodeFence(_ line: String, matching opening: PendingCodeFence) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == opening.marker else { return false }

        let count = trimmed.prefix { $0 == opening.marker }.count
        guard count >= opening.length else { return false }

        let trailing = trimmed.dropFirst(count)
        return trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func parseIndentedCodeBlock(at startIndex: Int, lines: [String]) -> ParsedIndentedCodeBlock? {
        guard startIndex < lines.count else { return nil }
        let firstLine = lines[startIndex]
        guard !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard countLeadingIndent(firstLine) >= 4 else { return nil }

        var codeLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                codeLines.append("")
                index += 1
                continue
            }

            let indent = countLeadingIndent(line)
            guard indent >= 4 else { break }

            codeLines.append(stripLeadingIndent(line, count: 4))
            index += 1
        }

        while codeLines.last == "" {
            codeLines.removeLast()
        }

        return ParsedIndentedCodeBlock(code: codeLines.joined(separator: "\n"), linesConsumed: index - startIndex)
    }

    private static func countLeadingIndent(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " || character == "\t" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func stripLeadingIndent(_ line: String, count: Int) -> String {
        guard count > 0 else { return line }

        var index = line.startIndex
        var remaining = count

        while index < line.endIndex, remaining > 0 {
            let char = line[index]
            if char == " " || char == "\t" {
                index = line.index(after: index)
                remaining -= 1
            } else {
                break
            }
        }

        return String(line[index...])
    }

    private static func trimOuterBlankLines(_ lines: [String]) -> [String] {
        var start = 0
        var end = lines.count

        while start < end, lines[start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            start += 1
        }

        while end > start, lines[end - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            end -= 1
        }

        return Array(lines[start..<end])
    }

    private static func parseTable(at startIndex: Int, lines: [String]) -> ParsedTable? {
        guard startIndex + 2 < lines.count else { return nil }
        guard let headerCells = parseTableCells(from: lines[startIndex]), !headerCells.isEmpty else { return nil }
        guard let alignments = parseDividerRow(lines[startIndex + 1], expectedColumnCount: headerCells.count) else { return nil }

        var rowCells: [[String]] = []
        var index = startIndex + 2

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }

            guard let cells = parseTableCells(from: line) else {
                break
            }

            rowCells.append(normalizedTableCells(cells, columnCount: headerCells.count))
            index += 1
        }

        guard !rowCells.isEmpty else { return nil }

        let table = TableData(
            headers: headerCells.map { render($0) },
            rows: rowCells.map { $0.map { render($0) } },
            alignments: alignments
        )
        return ParsedTable(data: table, linesConsumed: index - startIndex)
    }

    private static func parseDividerRow(_ line: String, expectedColumnCount: Int) -> [TableColumnAlignment]? {
        guard let cells = parseTableCells(from: line), cells.count == expectedColumnCount else { return nil }

        var alignments: [TableColumnAlignment] = []
        alignments.reserveCapacity(cells.count)

        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { return nil }

            let leadingColon = trimmed.hasPrefix(":")
            let trailingColon = trimmed.hasSuffix(":")
            let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

            guard core.count >= 3, core.allSatisfy({ $0 == "-" }) else { return nil }

            switch (leadingColon, trailingColon) {
            case (true, true):
                alignments.append(.center)
            case (false, true):
                alignments.append(.trailing)
            default:
                alignments.append(.leading)
            }
        }

        return alignments
    }

    private static func parseTableCells(from line: String) -> [String]? {
        let escapedPipePlaceholder = "\u{001F}"
        let escaped = line.replacingOccurrences(of: "\\|", with: escapedPipePlaceholder)
        guard escaped.contains("|") else { return nil }

        var content = escaped.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }

        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { part in
                part
                    .replacingOccurrences(of: escapedPipePlaceholder, with: "|")
                    .trimmingCharacters(in: .whitespaces)
            }

        return cells.isEmpty ? nil : cells
    }

    private static func normalizedTableCells(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count == columnCount {
            return cells
        }
        if cells.count > columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }
}

private struct MarkdownBlocksStack: View {
    let blocks: [MessageMarkdownRenderer.Block]
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MessageMarkdownRenderer.Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading(let level, let text):
            Text(text)
                .font(font(for: level))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .horizontalRule:
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        case .blockquote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 3)

                MarkdownBlocksStack(blocks: blocks, spacing: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        listMarker(item)
                            .frame(minWidth: 24, alignment: .trailing)

                        if item.blocks.isEmpty {
                            Text("")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownBlocksStack(blocks: item.blocks, spacing: 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 8) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: true, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .table(let table):
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(table.alignments.enumerated()), id: \.offset) { index, alignment in
                            let cell = table.headers[index]
                            tableCell(
                                cell,
                                alignment: alignment,
                                emphasized: true,
                                showTrailingDivider: index < table.alignments.count - 1
                            )
                        }
                    }
                    .background(Color.secondary.opacity(0.06))

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                        .gridCellColumns(table.alignments.count)

                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(Array(table.alignments.enumerated()), id: \.offset) { columnIndex, alignment in
                                let cell = columnIndex < row.count ? row[columnIndex] : AttributedString("")
                                tableCell(
                                    cell,
                                    alignment: alignment,
                                    emphasized: false,
                                    showTrailingDivider: columnIndex < table.alignments.count - 1
                                )
                            }
                        }
                        .background(Color.secondary.opacity(rowIndex.isMultiple(of: 2) ? 0.03 : 0.0))
                    }
                }
                .padding(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func listMarker(_ item: MessageMarkdownRenderer.ListItem) -> some View {
        if let task = item.task {
            Text(task == .checked ? "☑" : "☐")
                .fontWeight(.semibold)
        } else {
            Text(item.marker)
                .fontWeight(.semibold)
        }
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.semibold)
        case 2:
            return .title3.weight(.semibold)
        case 3:
            return .headline
        default:
            return .body.weight(.semibold)
        }
    }

    @ViewBuilder
    private func tableCell(
        _ cell: AttributedString,
        alignment: MessageMarkdownRenderer.TableColumnAlignment,
        emphasized: Bool,
        showTrailingDivider: Bool
    ) -> some View {
        Text(cell)
            .font(emphasized ? .body.weight(.semibold) : .body)
            .multilineTextAlignment(textAlignment(for: alignment))
            .frame(minWidth: 140, maxWidth: .infinity, alignment: frameAlignment(for: alignment))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(alignment: .trailing) {
                if showTrailingDivider {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 1)
                }
            }
    }

    private func frameAlignment(for alignment: MessageMarkdownRenderer.TableColumnAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func textAlignment(for alignment: MessageMarkdownRenderer.TableColumnAlignment) -> TextAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}
