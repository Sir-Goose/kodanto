import SwiftUI

extension DiffConfiguration {
    func with(theme: DiffTheme) -> DiffConfiguration {
        DiffConfiguration(
            theme: theme,
            showLineNumbers: showLineNumbers,
            showFileHeaders: showFileHeaders,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            lineHeight: lineHeight,
            lineSpacing: lineSpacing,
            wordWrap: wordWrap,
            contentPadding: contentPadding
        )
    }

    func withLineNumbers(_ show: Bool) -> DiffConfiguration {
        DiffConfiguration(
            theme: theme,
            showLineNumbers: show,
            showFileHeaders: showFileHeaders,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            lineHeight: lineHeight,
            lineSpacing: lineSpacing,
            wordWrap: wordWrap,
            contentPadding: contentPadding
        )
    }

    func withFont(size: CGFloat? = nil, weight: Font.Weight? = nil, design: Font.Design? = nil) -> DiffConfiguration {
        DiffConfiguration(
            theme: theme,
            showLineNumbers: showLineNumbers,
            showFileHeaders: showFileHeaders,
            fontFamily: design ?? fontFamily,
            fontSize: size ?? fontSize,
            fontWeight: weight ?? fontWeight,
            lineHeight: lineHeight,
            lineSpacing: lineSpacing,
            wordWrap: wordWrap,
            contentPadding: contentPadding
        )
    }

    func withLineSpacing(_ spacing: LineSpacing) -> DiffConfiguration {
        DiffConfiguration(
            theme: theme,
            showLineNumbers: showLineNumbers,
            showFileHeaders: showFileHeaders,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            lineHeight: lineHeight,
            lineSpacing: spacing,
            wordWrap: wordWrap,
            contentPadding: contentPadding
        )
    }

    func withWordWrap(_ wrap: Bool) -> DiffConfiguration {
        DiffConfiguration(
            theme: theme,
            showLineNumbers: showLineNumbers,
            showFileHeaders: showFileHeaders,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            lineHeight: lineHeight,
            lineSpacing: lineSpacing,
            wordWrap: wrap,
            contentPadding: contentPadding
        )
    }
}
