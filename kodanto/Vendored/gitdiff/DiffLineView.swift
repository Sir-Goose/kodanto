import SwiftUI

struct DiffLineView: View {
  let line: DiffLine

  @Environment(\.diffConfiguration) private var configuration

  private var backgroundColor: Color {
    switch line.type {
    case .added:
      return configuration.theme.addedBackground
    case .removed:
      return configuration.theme.removedBackground
    case .context:
      return configuration.theme.contextBackground
    case .header:
      return configuration.theme.headerBackground
    }
  }

  private var foregroundColor: Color {
    switch line.type {
    case .added:
      return configuration.theme.addedText
    case .removed:
      return configuration.theme.removedText
    case .context:
      return configuration.theme.contextText
    case .header:
      return configuration.theme.headerText
    }
  }

  private var linePrefix: String {
    switch line.type {
    case .added:
      return "+"
    case .removed:
      return "-"
    case .context, .header:
      return " "
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      if configuration.showLineNumbers {
        Text(line.oldLineNumber.map(String.init) ?? "")
          .font(.system(size: configuration.fontSize * 0.85, design: configuration.fontFamily))
          .foregroundColor(configuration.theme.lineNumberText)
          .frame(width: 20, alignment: .trailing)
          .padding(.horizontal, 4)
          .background(configuration.theme.lineNumberBackground)

        Text(line.newLineNumber.map(String.init) ?? "")
          .font(.system(size: configuration.fontSize * 0.85, design: configuration.fontFamily))
          .foregroundColor(configuration.theme.lineNumberText)
          .frame(width: 20, alignment: .trailing)
          .padding(.horizontal, 4)
          .background(configuration.theme.lineNumberBackground)
      }

      HStack(alignment: .top, spacing: 0) {
        Text(linePrefix)
          .font(.system(size: configuration.fontSize, weight: configuration.fontWeight, design: configuration.fontFamily))
          .foregroundColor(foregroundColor)
          .padding(.leading, configuration.contentPadding.leading)

        Text(line.content)
          .font(.system(size: configuration.fontSize, weight: configuration.fontWeight, design: configuration.fontFamily))
          .foregroundColor(foregroundColor)
          .padding(.leading, 4)
          .padding(.trailing, configuration.contentPadding.trailing)
          .fixedSize(horizontal: !configuration.wordWrap, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(backgroundColor)
    }
  }
}
