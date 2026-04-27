import Foundation

struct DiffFile: Identifiable {
  let id = UUID()
  let oldPath: String
  let newPath: String
  let hunks: [DiffHunk]
  let isBinary: Bool
  let isRenamed: Bool

  var displayName: String {
    if isRenamed {
      return "\(oldPath) → \(newPath)"
    }
    return newPath.isEmpty ? oldPath : newPath
  }
}
