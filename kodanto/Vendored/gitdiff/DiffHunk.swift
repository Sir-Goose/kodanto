import Foundation

struct DiffHunk: Identifiable {
  let id = UUID()
  let oldStart: Int
  let oldCount: Int
  let newStart: Int
  let newCount: Int
  let header: String
  let lines: [DiffLine]
}
