import Foundation

struct DiffLine: Identifiable {
  let id = UUID()
  let type: LineType
  let content: String
  let oldLineNumber: Int?
  let newLineNumber: Int?

  enum LineType {
    case added
    case removed
    case context
    case header
  }
}
