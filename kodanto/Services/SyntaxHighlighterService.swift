import AppKit
import SwiftUI

@MainActor
final class SyntaxHighlighterService {
    static let shared = SyntaxHighlighterService()

    private let highlighter: Highlighter?
    private var lastThemeWasDark: Bool?

    private init() {
        let hl = Highlighter()
        hl?.setTheme("xcode")
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        hl?.theme.setCodeFont(font)
        self.highlighter = hl
    }

    func highlight(_ code: String, as language: String?) -> AttributedString? {
        guard let highlighter else { return nil }
        applyThemeForCurrentAppearance()
        guard let result = highlighter.highlight(code, as: language) else { return nil }
        return AttributedString(result)
    }

    private func applyThemeForCurrentAppearance() {
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
        guard isDark != lastThemeWasDark else { return }
        let themeName = isDark ? "atom-one-dark" : "xcode"
        highlighter?.setTheme(themeName)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        highlighter?.theme.setCodeFont(font)
        lastThemeWasDark = isDark
    }
}
