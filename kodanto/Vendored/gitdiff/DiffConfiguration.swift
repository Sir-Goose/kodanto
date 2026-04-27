import SwiftUI

public struct DiffConfiguration {
    public let theme: DiffTheme
    public let showLineNumbers: Bool
    public let showFileHeaders: Bool
    public let fontFamily: Font.Design
    public let fontSize: CGFloat
    public let fontWeight: Font.Weight
    public let lineHeight: CGFloat
    public let lineSpacing: LineSpacing
    public let wordWrap: Bool
    public let contentPadding: EdgeInsets

    public enum LineSpacing {
        case compact
        case comfortable
        case spacious

        var value: CGFloat {
            switch self {
            case .compact: return 0
            case .comfortable: return 2
            case .spacious: return 4
            }
        }
    }

    public init(
        theme: DiffTheme = .light,
        showLineNumbers: Bool = true,
        showFileHeaders: Bool = true,
        fontFamily: Font.Design = .monospaced,
        fontSize: CGFloat = 13,
        fontWeight: Font.Weight = .regular,
        lineHeight: CGFloat = 1.2,
        lineSpacing: LineSpacing = .compact,
        wordWrap: Bool = true,
        contentPadding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    ) {
        self.theme = theme
        self.showLineNumbers = showLineNumbers
        self.showFileHeaders = showFileHeaders
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.lineSpacing = lineSpacing
        self.wordWrap = wordWrap
        self.contentPadding = contentPadding
    }
}

extension DiffConfiguration {
    static let `default` = DiffConfiguration()
    static let compact = DiffConfiguration(
        fontSize: 12,
        lineSpacing: .compact,
        contentPadding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
    )
    static let comfortable = DiffConfiguration(
        fontSize: 14,
        lineSpacing: .comfortable,
        contentPadding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    )
}
