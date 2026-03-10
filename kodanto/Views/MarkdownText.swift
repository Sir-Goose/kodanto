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
    }

    struct ListItem: Equatable {
        let marker: String
        let content: AttributedString
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

        for line in lines {
            if var codeBlock = pendingCodeBlock {
                if isFenceDelimiter(line) {
                    blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.lines.joined(separator: "\n")))
                    pendingCodeBlock = nil
                } else {
                    codeBlock.lines.append(line)
                    pendingCodeBlock = codeBlock
                }
                continue
            }

            if let codeBlock = openingCodeBlock(from: line) {
                flushParagraph()
                flushList()
                pendingCodeBlock = codeBlock
                continue
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let heading = parseHeading(from: line) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, text: render(heading.text)))
                continue
            }

            if let listItem = parseListItem(from: line) {
                flushParagraph()
                if let currentListKind, currentListKind != listItem.kind {
                    flushList()
                }
                currentListKind = listItem.kind
                pendingListItems.append(PendingListItem(marker: listItem.marker, lines: [listItem.content]))
                continue
            }

            if !pendingListItems.isEmpty, isListContinuation(line) {
                var item = pendingListItems.removeLast()
                item.lines.append(line.trimmingCharacters(in: .whitespaces))
                pendingListItems.append(item)
                continue
            }

            flushList()
            paragraphLines.append(line)
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
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
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
}
