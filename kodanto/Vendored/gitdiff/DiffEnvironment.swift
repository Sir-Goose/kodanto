import SwiftUI

struct DiffConfigurationKey: EnvironmentKey {
    static let defaultValue = DiffConfiguration.default
}

extension EnvironmentValues {
    var diffConfiguration: DiffConfiguration {
        get { self[DiffConfigurationKey.self] }
        set { self[DiffConfigurationKey.self] = newValue }
    }
}

extension View {
    func diffConfiguration(_ configuration: DiffConfiguration) -> some View {
        environment(\.diffConfiguration, configuration)
    }

    func diffTheme(_ theme: DiffTheme) -> some View {
        transformEnvironment(\.diffConfiguration) { config in
            config = DiffConfiguration(
                theme: theme,
                showLineNumbers: config.showLineNumbers,
                showFileHeaders: config.showFileHeaders,
                fontFamily: config.fontFamily,
                fontSize: config.fontSize,
                fontWeight: config.fontWeight,
                lineHeight: config.lineHeight,
                lineSpacing: config.lineSpacing,
                wordWrap: config.wordWrap,
                contentPadding: config.contentPadding
            )
        }
    }

    func diffLineNumbers(_ show: Bool) -> some View {
        transformEnvironment(\.diffConfiguration) { config in
            config = DiffConfiguration(
                theme: config.theme,
                showLineNumbers: show,
                showFileHeaders: config.showFileHeaders,
                fontFamily: config.fontFamily,
                fontSize: config.fontSize,
                fontWeight: config.fontWeight,
                lineHeight: config.lineHeight,
                lineSpacing: config.lineSpacing,
                wordWrap: config.wordWrap,
                contentPadding: config.contentPadding
            )
        }
    }

    func diffFont(size: CGFloat? = nil, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        transformEnvironment(\.diffConfiguration) { config in
            config = DiffConfiguration(
                theme: config.theme,
                showLineNumbers: config.showLineNumbers,
                showFileHeaders: config.showFileHeaders,
                fontFamily: design ?? config.fontFamily,
                fontSize: size ?? config.fontSize,
                fontWeight: weight ?? config.fontWeight,
                lineHeight: config.lineHeight,
                lineSpacing: config.lineSpacing,
                wordWrap: config.wordWrap,
                contentPadding: config.contentPadding
            )
        }
    }

    func diffLineSpacing(_ spacing: DiffConfiguration.LineSpacing) -> some View {
        transformEnvironment(\.diffConfiguration) { config in
            config = DiffConfiguration(
                theme: config.theme,
                showLineNumbers: config.showLineNumbers,
                showFileHeaders: config.showFileHeaders,
                fontFamily: config.fontFamily,
                fontSize: config.fontSize,
                fontWeight: config.fontWeight,
                lineHeight: config.lineHeight,
                lineSpacing: spacing,
                wordWrap: config.wordWrap,
                contentPadding: config.contentPadding
            )
        }
    }

    func diffWordWrap(_ wrap: Bool) -> some View {
        transformEnvironment(\.diffConfiguration) { config in
            config = DiffConfiguration(
                theme: config.theme,
                showLineNumbers: config.showLineNumbers,
                showFileHeaders: config.showFileHeaders,
                fontFamily: config.fontFamily,
                fontSize: config.fontSize,
                fontWeight: config.fontWeight,
                lineHeight: config.lineHeight,
                lineSpacing: config.lineSpacing,
                wordWrap: wrap,
                contentPadding: config.contentPadding
            )
        }
    }
}
