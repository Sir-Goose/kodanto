import Foundation
import SwiftUI

struct MarkdownText: View, Equatable {
    let text: String

    var body: some View {
        let blocks = MessageMarkdownRenderer.parseBlocks(text)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum MessageMarkdownRenderer {
    private final class CachedBlocks: NSObject {
        let blocks: [Block]

        init(blocks: [Block]) {
            self.blocks = blocks
        }
    }

    enum Block: Equatable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        case list(items: [ListItem])
        case codeBlock(language: String?, code: String)
        case table(TableData)
    }

    struct ListItem: Equatable {
        let marker: String
        let content: AttributedString
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

        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var currentListKind: PendingListKind?
        var pendingListItems: [PendingListItem] = []
        var pendingCodeBlock: PendingCodeBlock?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines.joined(separator: "\n")
            if !paragraph.isEmpty {
                blocks.append(.paragraph(render(paragraph)))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard !pendingListItems.isEmpty else { return }
            blocks.append(.list(items: pendingListItems.map { item in
                ListItem(marker: item.marker, content: render(item.lines.joined(separator: "\n")))
            }))
            currentListKind = nil
            pendingListItems.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if var codeBlock = pendingCodeBlock {
                if isFenceDelimiter(line) {
                    blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.lines.joined(separator: "\n")))
                    pendingCodeBlock = nil
                } else {
                    codeBlock.lines.append(line)
                    pendingCodeBlock = codeBlock
                }
                index += 1
                continue
            }

            if let codeBlock = openingCodeBlock(from: line) {
                flushParagraph()
                flushList()
                pendingCodeBlock = codeBlock
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if let table = parseTable(at: index, lines: lines) {
                flushParagraph()
                flushList()
                blocks.append(.table(table.data))
                index += table.linesConsumed
                continue
            }

            if let heading = parseHeading(from: line) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, text: render(heading.text)))
                index += 1
                continue
            }

            if let listItem = parseListItem(from: line) {
                flushParagraph()
                if let currentListKind, currentListKind != listItem.kind {
                    flushList()
                }
                currentListKind = listItem.kind
                pendingListItems.append(PendingListItem(marker: listItem.marker, lines: [listItem.content]))
                index += 1
                continue
            }

            if !pendingListItems.isEmpty, isListContinuation(line) {
                var item = pendingListItems.removeLast()
                item.lines.append(line.trimmingCharacters(in: .whitespaces))
                pendingListItems.append(item)
                index += 1
                continue
            }

            flushList()
            paragraphLines.append(line)
            index += 1
        }

        if let codeBlock = pendingCodeBlock {
            blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.lines.joined(separator: "\n")))
        }

        flushParagraph()
        flushList()

        if blocks.isEmpty, !text.isEmpty {
            return [.paragraph(AttributedString(text))]
        }

        return blocks
    }

    private enum PendingListKind: Equatable {
        case unordered
        case ordered
    }

    private struct PendingListItem {
        let marker: String
        var lines: [String]
    }

    private struct PendingCodeBlock {
        let language: String?
        var lines: [String]
    }

    private struct Heading {
        let level: Int
        let text: String
    }

    private struct ParsedListItem {
        let kind: PendingListKind
        let marker: String
        let content: String
    }

    private struct ParsedTable {
        let data: TableData
        let linesConsumed: Int
    }

    private static func openingCodeBlock(from line: String) -> PendingCodeBlock? {
        guard isFenceDelimiter(line) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let language = trimmed
            .dropFirst(3)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)

        return PendingCodeBlock(language: language, lines: [])
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func parseHeading(from line: String) -> Heading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }

        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }

        return Heading(level: hashes.count, text: String(remainder.dropFirst()))
    }

    private static func parseListItem(from line: String) -> ParsedListItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for marker in ["-", "*", "+"] {
            if trimmed.hasPrefix("\(marker) ") {
                return ParsedListItem(
                    kind: .unordered,
                    marker: "•",
                    content: String(trimmed.dropFirst(2))
                )
            }
        }

        let digits = trimmed.prefix { $0.wholeNumberValue != nil }
        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        guard remainder.first == ".", remainder.dropFirst().first == " " else { return nil }

        return ParsedListItem(
            kind: .ordered,
            marker: "\(digits).",
            content: String(remainder.dropFirst(2))
        )
    }

    private static func isListContinuation(_ line: String) -> Bool {
        let prefix = line.prefix { $0 == " " || $0 == "\t" }
        return prefix.contains("\t") || prefix.count >= 2
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
            let core = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

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
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker)
                            .fontWeight(.semibold)
                        Text(item.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
