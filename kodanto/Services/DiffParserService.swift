import Foundation

enum DiffParserService {
    static func computeDiff(from before: String, to after: String, filePath: String = "file") -> String {
        let header = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        guard before != after else {
            return header
        }

        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false)

        let diff = computeHunks(before: beforeLines.map(String.init), after: afterLines.map(String.init))
        guard !diff.isEmpty else { return header }

        return header + diff
    }

    static func languageForFile(_ filePath: String) -> String? {
        let ext = (filePath as NSString).pathExtension.lowercased()
        return languageMap[ext]
    }
}

private extension DiffParserService {
    struct DiffHunkData {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        let lines: [String]

        var header: String {
            "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        }
    }

    static func computeHunks(before: [String], after: [String]) -> String {
        let ses = computeSES(before: before, after: after)
        guard !ses.isEmpty else { return "" }

        let hunks = chunkIntoHunks(ses: ses, contextLines: 3)
        return hunks.map(renderHunk).joined()
    }

    struct SESEntry {
        enum Kind { case same, delete, insert }
        let kind: Kind
        let text: String
    }

    static func computeSES(before: [String], after: [String]) -> [SESEntry] {
        let n = before.count
        let m = after.count
        guard n > 0 || m > 0 else { return [] }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n {
            for j in 0...m {
                if i == 0 {
                    dp[i][j] = j
                } else if j == 0 {
                    dp[i][j] = i
                } else if before[i - 1] == after[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [SESEntry] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && before[i - 1] == after[j - 1] {
                result.append(SESEntry(kind: .same, text: String(before[i - 1])))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] <= dp[i - 1][j]) {
                result.append(SESEntry(kind: .insert, text: String(after[j - 1])))
                j -= 1
            } else if i > 0 {
                result.append(SESEntry(kind: .delete, text: String(before[i - 1])))
                i -= 1
            }
        }

        return result.reversed()
    }

    static func chunkIntoHunks(ses: [SESEntry], contextLines: Int) -> [DiffHunkData] {
        var hunks: [DiffHunkData] = []
        var currentLines: [String] = []
        var oldLine = 1, newLine = 1
        var hunkOldStart = 1, hunkNewStart = 1
        var inHunk = false
        var trailingContext = 0

        func flushHunk() {
            guard inHunk, !currentLines.isEmpty else { return }

            let oldCount = currentLines.filter { $0.first != "+" }.count
            let newCount = currentLines.filter { $0.first != "-" }.count
            let header = "@@ -\(hunkOldStart),\(oldCount) +\(hunkNewStart),\(newCount) @@\n"

            var lines = currentLines
            while let last = lines.last, last.hasPrefix(" ") {
                lines.removeLast()
            }

            hunks.append(DiffHunkData(
                oldStart: hunkOldStart, oldCount: oldCount,
                newStart: hunkNewStart, newCount: newCount,
                lines: lines
            ))
            currentLines.removeAll()
            inHunk = false
        }

        for entry in ses {
            switch entry.kind {
            case .same:
                if inHunk {
                    if trailingContext < contextLines {
                        currentLines.append(" \(entry.text)")
                        trailingContext += 1
                        oldLine += 1; newLine += 1
                    } else {
                        flushHunk()
                        oldLine += 1; newLine += 1
                    }
                } else {
                    oldLine += 1; newLine += 1
                }

            case .delete:
                if !inHunk {
                    hunkOldStart = oldLine
                    hunkNewStart = newLine
                    inHunk = true
                    trailingContext = 0
                }
                currentLines.append("-\(entry.text)")
                oldLine += 1

            case .insert:
                if !inHunk {
                    hunkOldStart = oldLine
                    hunkNewStart = newLine
                    inHunk = true
                    trailingContext = 0
                }
                currentLines.append("+\(entry.text)")
                newLine += 1
            }
        }

        flushHunk()
        return hunks
    }

    static func renderHunk(_ hunk: DiffHunkData) -> String {
        guard !hunk.lines.isEmpty else { return "" }
        var result = hunk.header
        for line in hunk.lines {
            result += line + "\n"
        }
        return result
    }
}

private let languageMap: [String: String] = [
    "swift": "swift",
    "ts": "typescript",
    "tsx": "typescript",
    "js": "javascript",
    "jsx": "javascript",
    "py": "python",
    "go": "go",
    "rs": "rust",
    "rb": "ruby",
    "kt": "kotlin",
    "java": "java",
    "cs": "csharp",
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "hpp": "cpp",
    "cc": "cpp",
    "css": "css",
    "scss": "scss",
    "html": "html",
    "htm": "html",
    "json": "json",
    "yaml": "yaml",
    "yml": "yaml",
    "toml": "toml",
    "md": "markdown",
    "sh": "bash",
    "bash": "bash",
    "zsh": "bash",
    "sql": "sql",
    "graphql": "graphql",
    "gql": "graphql",
    "proto": "protobuf",
    "dart": "dart",
    "lua": "lua",
    "php": "php",
    "r": "r",
    "ml": "ocaml",
    "ex": "elixir",
    "exs": "elixir",
    "hs": "haskell",
    "zig": "zig",
    "svelte": "svelte",
    "vue": "vue",
    "astro": "astro",
]