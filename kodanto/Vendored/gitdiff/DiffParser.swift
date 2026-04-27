import Foundation

class DiffParser {
  static func parse(_ diffText: String) async throws -> [DiffFile] {
    let lines = diffText.components(separatedBy: .newlines)
    var files: [DiffFile] = []
    var currentFileLines: [String] = []
    var i = 0

    while i < lines.count {
      try Task.checkCancellation()
      let line = lines[i]

      if line.hasPrefix("diff --git") {
        if !currentFileLines.isEmpty {
          if let file = try await parseFile(currentFileLines) {
            files.append(file)
          }
          currentFileLines = []
        }
        currentFileLines.append(line)
      } else if !currentFileLines.isEmpty {
        currentFileLines.append(line)
      }

      i += 1
    }

    if !currentFileLines.isEmpty {
      if let file = try await parseFile(currentFileLines) {
        files.append(file)
      }
    }

    return files
  }

  private static func parseFile(_ lines: [String]) async throws -> DiffFile? {
    guard !lines.isEmpty else { return nil }

    var oldPath = ""
    var newPath = ""
    var hunks: [DiffHunk] = []
    var isBinary = false
    var isRenamed = false
    var i = 0

    while i < lines.count {
      try Task.checkCancellation()
      let line = lines[i]

      if line.hasPrefix("diff --git") {
        let paths = extractPaths(from: line)
        oldPath = paths.old
        newPath = paths.new
      } else if line.hasPrefix("rename from") {
        isRenamed = true
        oldPath = String(line.dropFirst("rename from ".count))
      } else if line.hasPrefix("rename to") {
        newPath = String(line.dropFirst("rename to ".count))
      } else if line.hasPrefix("--- ") {
        if line == "--- /dev/null" {
          oldPath = "/dev/null"
        } else {
          oldPath = String(line.dropFirst(4))
          if oldPath.hasPrefix("a/") {
            oldPath = String(oldPath.dropFirst(2))
          }
        }
      } else if line.hasPrefix("+++ ") {
        if line == "+++ /dev/null" {
          newPath = "/dev/null"
        } else {
          newPath = String(line.dropFirst(4))
          if newPath.hasPrefix("b/") {
            newPath = String(newPath.dropFirst(2))
          }
        }
      } else if line.contains("Binary files") {
        isBinary = true
        break
      } else if line.hasPrefix("@@") {
        break
      }

      i += 1
    }

    while i < lines.count {
      if lines[i].hasPrefix("@@") {
        if let hunk = parseHunk(Array(lines[i..<lines.count])) {
          hunks.append(hunk)
          i += hunk.lines.count + 1
        } else {
          i += 1
        }
      } else {
        i += 1
      }
    }

    return DiffFile(
      oldPath: oldPath,
      newPath: newPath,
      hunks: hunks,
      isBinary: isBinary,
      isRenamed: isRenamed
    )
  }

  private static func parseHunk(_ lines: [String]) -> DiffHunk? {
    guard !lines.isEmpty, lines[0].hasPrefix("@@") else { return nil }

    let header = lines[0]
    let hunkInfo = parseHunkHeader(header)
    var hunkLines: [DiffLine] = []
    var oldLineNum = hunkInfo.oldStart
    var newLineNum = hunkInfo.newStart

    for i in 1..<lines.count {
      let line = lines[i]

      if line.hasPrefix("@@") || line.hasPrefix("diff --git") {
        break
      }

      let firstChar = line.first ?? " "
      let content = line.isEmpty ? "" : String(line.dropFirst())

      switch firstChar {
      case "+":
        hunkLines.append(DiffLine(
          type: .added,
          content: content,
          oldLineNumber: nil,
          newLineNumber: newLineNum
        ))
        newLineNum += 1
      case "-":
        hunkLines.append(DiffLine(
          type: .removed,
          content: content,
          oldLineNumber: oldLineNum,
          newLineNumber: nil
        ))
        oldLineNum += 1
      default:
        hunkLines.append(DiffLine(
          type: .context,
          content: line.isEmpty ? "" : (line.hasPrefix(" ") ? String(line.dropFirst()) : line),
          oldLineNumber: oldLineNum,
          newLineNumber: newLineNum
        ))
        oldLineNum += 1
        newLineNum += 1
      }
    }

    return DiffHunk(
      oldStart: hunkInfo.oldStart,
      oldCount: hunkInfo.oldCount,
      newStart: hunkInfo.newStart,
      newCount: hunkInfo.newCount,
      header: header,
      lines: hunkLines
    )
  }

  private static func parseHunkHeader(_ header: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
    let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#

    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
      return (1, 0, 1, 0)
    }

    let oldStart = Int(header[Range(match.range(at: 1), in: header)!]) ?? 1
    let oldCount = match.range(at: 2).location != NSNotFound ? Int(header[Range(match.range(at: 2), in: header)!]) ?? 0 : 1
    let newStart = Int(header[Range(match.range(at: 3), in: header)!]) ?? 1
    let newCount = match.range(at: 4).location != NSNotFound ? Int(header[Range(match.range(at: 4), in: header)!]) ?? 0 : 1

    return (oldStart, oldCount, newStart, newCount)
  }

  private static func extractPaths(from diffLine: String) -> (old: String, new: String) {
    let parts = diffLine.components(separatedBy: " ")
    guard parts.count >= 4 else { return ("", "") }

    var oldPath = parts[2]
    var newPath = parts[3]

    if oldPath.hasPrefix("a/") {
      oldPath = String(oldPath.dropFirst(2))
    }
    if newPath.hasPrefix("b/") {
      newPath = String(newPath.dropFirst(2))
    }

    return (oldPath, newPath)
  }
}
