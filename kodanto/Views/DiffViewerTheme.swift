import SwiftUI

extension DiffTheme {
    static var kodanto: DiffTheme {
        DiffTheme(
            addedBackground: Color.green.opacity(0.15),
            addedText: Color(NSColor.labelColor),
            removedBackground: Color.red.opacity(0.12),
            removedText: Color(NSColor.labelColor),
            contextBackground: Color.clear,
            contextText: Color(NSColor.labelColor),
            lineNumberBackground: Color.clear,
            lineNumberText: Color.secondary,
            headerBackground: Color.secondary.opacity(0.07),
            headerText: Color.secondary,
            fileHeaderBackground: Color.clear,
            fileHeaderText: Color.primary
        )
    }
}