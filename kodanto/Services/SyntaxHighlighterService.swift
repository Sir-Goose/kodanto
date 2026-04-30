import AppKit
import SwiftUI

@MainActor
final class SyntaxHighlighterService {
    static let shared = SyntaxHighlighterService()

    private let highlighter: Highlighter?

    private init() {
        let hl = Highlighter()
        hl?.setTheme("xcode")
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        hl?.theme.setCodeFont(font)
        self.highlighter = hl
    }

    func highlight(_ code: String, as language: String?) -> AttributedString? {
        guard let highlighter else { return nil }
        guard let result = highlighter.highlight(code, as: language) else { return nil }
        return AttributedString(result)
    }
}
